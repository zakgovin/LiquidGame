// Hydrologic: native 3D position-based liquid solver.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <unordered_map>
#include <vector>

using namespace godot;
namespace {
struct Cell { int x,y,z; bool operator==(const Cell &o) const { return x==o.x && y==o.y && z==o.z; } };
struct CellHash { size_t operator()(const Cell &c) const { return size_t(uint32_t(c.x)*73856093u ^ uint32_t(c.y)*19349663u ^ uint32_t(c.z)*83492791u); } };
inline float clampf(float v,float a,float b){return std::max(a,std::min(b,v));}
inline float signf(float v){return v<0?-1.f:(v>0?1.f:0.f);}
inline Vector3 limited(Vector3 v,float max){float len=v.length_squared();return len>max*max?v*(max/std::sqrt(len)):v;}
}

class NativeLiquidSolver : public RefCounted {
 GDCLASS(NativeLiquidSolver, RefCounted)
 std::vector<Rect2> floors;
 std::vector<float> elevations;
 std::vector<std::array<float,6>> walls;
 struct TerrainTile { Rect2 rectangle; float height; };
 std::vector<TerrainTile> tiles;
 Rect2 bounds,spawn,goal;
 int count=0,iterations=3,lost=0;
 float top=.82f,base=-.55f,radius=.052f,spacing=.1f,h=.22f,rho=6.8f,drag=.04f,max_speed=3.2f,viscosity=1.f;
 float fraction=0,held=0,required=.8f,hold_seconds=.75f;
 bool completed=false;
 std::vector<Vector3> positions,velocities,previous,corrections,contacts,smoothed,boundary_gradient;
 std::vector<float> lambdas,densities,inverse_density;
 std::vector<uint8_t> active;
 std::vector<std::vector<int>> neighbors;
 std::unordered_map<Cell,std::vector<int>,CellHash> grid;
 std::array<float,65> wall_table{};

 float floor_height(Vector2 p) const {
  if(!bounds.has_point(p))return -std::numeric_limits<float>::infinity();
  float value=top;
  for(size_t i=0;i<floors.size();++i)if(floors[i].has_point(p))value=std::min(value,elevations[i]);
  return value;
 }
 Vector3 constrain_world(Vector3 p,Vector3) const {
  if(!bounds.grow(radius).has_point(Vector2(p.x,p.z)))return p;
  for(const auto &tile:tiles){
   const Rect2 &r=tile.rectangle;
   if(p.y>=tile.height+radius || p.y<base-radius || !r.grow(radius).has_point(Vector2(p.x,p.z)))continue;
   Vector3 lower(r.position.x,base,r.position.y),upper(r.get_end().x,tile.height,r.get_end().y);
   Vector3 nearest(clampf(p.x,lower.x,upper.x),clampf(p.y,lower.y,upper.y),clampf(p.z,lower.z,upper.z));
   Vector3 difference=p-nearest;float distance=difference.length();
   if(distance>=radius)continue;
   if(distance>1e-6f)p+=difference*(radius/distance-1);
   else{
    Vector3 exits[5]={Vector3(0,upper.y+radius-p.y,0),Vector3(lower.x-radius-p.x,0,0),Vector3(upper.x+radius-p.x,0,0),Vector3(0,0,lower.z-radius-p.z),Vector3(0,0,upper.z+radius-p.z)};
    Vector3 best=exits[0];for(auto candidate:exits)if(candidate.length_squared()<best.length_squared())best=candidate;p+=best;
   }
  }
  return p;
 }
 void constrain(int i){
  Vector3 bounded=constrain_world(positions[i],previous[i]);Vector3 out=positions[i]-bounded;
  if(std::abs(out.x)>1e-7f)contacts[i].x=signf(out.x);
  if(std::abs(out.y)>1e-7f)contacts[i].y=signf(out.y);
  if(std::abs(out.z)>1e-7f)contacts[i].z=signf(out.z);
  positions[i]=bounded;
 }
 Vector2 wall_fraction(float distance) const {
  if(distance>=h)return Vector2(1,0);
  float index=clampf(distance/h*64,0,63.9999f);int low=int(std::floor(index));
  float delta=wall_table[low+1]-wall_table[low];
  return Vector2(wall_table[low]+delta*(index-low),delta*64/h);
 }
 Vector4 wall_kernel(Vector3 p) const {
  float dx=h,dz=h,nx=0,nz=0;
  for(const auto &w:walls){
   if(p.y>w[5] || p.y<w[4]-h)continue;
   if(std::abs(w[0]-w[2])<.0001f && p.z>=w[1] && p.z<=w[3]){
    float d=std::abs(p.x-w[0]);if(d<dx){dx=d;nx=signf(p.x-w[0]);}
   }else if(std::abs(w[1]-w[3])<.0001f && p.x>=w[0] && p.x<=w[2]){
    float d=std::abs(p.z-w[1]);if(d<dz){dz=d;nz=signf(p.z-w[1]);}
   }
  }
  float fy_height=floor_height(Vector2(p.x,p.z));
  Vector2 fx=wall_fraction(dx),fz=wall_fraction(dz),fy=std::isfinite(fy_height)?wall_fraction(p.y-fy_height):Vector2(1,0);
  return Vector4(fx.x*fy.x*fz.x,fx.y*nx*fy.x*fz.x,fy.y*fx.x*fz.x,fz.y*nz*fx.x*fy.x);
 }
 void build_neighbors(){
  grid.clear();float search=h+spacing*.6f,s2=search*search;
  for(int i=0;i<count;++i)if(active[i]){
   auto p=positions[i];Cell c{int(std::floor(p.x/search)),int(std::floor(p.y/search)),int(std::floor(p.z/search))};grid[c].push_back(i);
  }
  for(int i=0;i<count;++i){
   auto &list=neighbors[i];list.clear();if(!active[i])continue;
   auto p=positions[i];Cell c{int(std::floor(p.x/search)),int(std::floor(p.y/search)),int(std::floor(p.z/search))};
   for(int y=-1;y<=1;++y)for(int z=-1;z<=1;++z)for(int x=-1;x<=1;++x){
    auto it=grid.find(Cell{c.x+x,c.y+y,c.z+z});if(it==grid.end())continue;
    for(int j:it->second)if(i!=j && p.distance_squared_to(positions[j])<s2)list.push_back(j);
   }
  }
 }
 void substep(float dt,Vector3 gravity){
  float h2=h*h,gradient_scale=-6/h2;
  std::fill(contacts.begin(),contacts.end(),Vector3());
  for(int i=0;i<count;++i)if(active[i]){previous[i]=positions[i];velocities[i]=limited((velocities[i]+gravity*dt)*std::exp(-drag*dt),max_speed);positions[i]+=velocities[i]*dt;constrain(i);}
  build_neighbors();
  for(int iteration=0;iteration<iterations;++iteration){
   for(int i=0;i<count;++i)if(active[i]){
    Vector4 wall=wall_kernel(positions[i]);float inv=1/(rho*wall.x);inverse_density[i]=inv;
    float density=1,gradient_sum=0;Vector3 gradient_i;
    for(int j:neighbors[i]){
     Vector3 difference=positions[i]-positions[j];float q=1-difference.length_squared()/h2;if(q<=0)continue;
     density+=q*q*q;Vector3 grad=difference*(gradient_scale*q*q*inv);gradient_i+=grad;gradient_sum+=grad.length_squared();
    }
    boundary_gradient[i]=Vector3(wall.y,wall.z,wall.w)*(-density*inv/wall.x);gradient_i+=boundary_gradient[i];densities[i]=density/wall.x;
    float compression=std::max(density*inv-1,0.f);lambdas[i]=-compression/(gradient_sum+gradient_i.length_squared()+.8f);
   }
   for(int i=0;i<count;++i)if(active[i]){
    Vector3 correction=boundary_gradient[i]*lambdas[i];
    for(int j:neighbors[i]){
     Vector3 difference=positions[i]-positions[j];float q=1-difference.length_squared()/h2;if(q<=0)continue;
     correction+=difference*(gradient_scale*q*q*(lambdas[i]*inverse_density[i]+lambdas[j]*inverse_density[j]));
    }
    corrections[i]=limited(correction,spacing*.45f);
   }
   for(int i=0;i<count;++i)if(active[i]){positions[i]+=corrections[i];constrain(i);}
  }
  for(int i=0;i<count;++i)if(active[i]){
   Vector3 v=limited((positions[i]-previous[i])/dt,max_speed),n=contacts[i];
   if(v.x*n.x>0)v.x=0;if(v.y*n.y>0)v.y=0;if(v.z*n.z>0)v.z=0;velocities[i]=v;
  }
  float smoothing=1-std::exp(-viscosity*dt);
  for(int i=0;i<count;++i)if(active[i]){
   Vector3 change;
   for(int j:neighbors[i]){float q=1-positions[i].distance_squared_to(positions[j])/h2;if(q>0)change+=(velocities[j]-velocities[i])*(q*q*q/std::max(densities[j],1.f));}
   smoothed[i]=velocities[i]+change*smoothing;
  }
  for(int i=0;i<count;++i)if(active[i]){
   velocities[i]=smoothed[i];auto p=positions[i];
   if(p.y<base-1.3f || !bounds.grow(1.25f).has_point(Vector2(p.x,p.z))){active[i]=0;++lost;}
  }
 }

 static constexpr int SX=98,SZ=148,SY=56,SLICE=SX*SZ,TOTAL=SLICE*SY;
 std::vector<float> surface_field,surface_floor;
 std::vector<Vector3> surface_gradient,surface_vertices,surface_normals;
 std::vector<uint8_t> surface_flags;
 std::vector<int> surface_touched,surface_cells;
 Dictionary make_surface(){
  constexpr float cell=.075f,iso=.65f,radius2=.18f*.18f;const Vector3 origin(-3.6f,-1.5f,-5.5f);
  if(surface_field.empty()){
   surface_field.assign(TOTAL,0);surface_gradient.assign(TOTAL,Vector3());surface_flags.assign(TOTAL,0);surface_floor.resize(SLICE);
   for(int z=0;z<SZ;++z)for(int x=0;x<SX;++x)surface_floor[z*SX+x]=floor_height(Vector2(origin.x+x*cell,origin.z+z*cell));
   surface_vertices.reserve(25000);surface_normals.reserve(25000);
  }
  for(int i:surface_touched){surface_field[i]=0;surface_gradient[i]=Vector3();}
  for(int i:surface_cells)surface_flags[i]=0;
  surface_touched.clear();surface_cells.clear();surface_vertices.clear();surface_normals.clear();
  const int offsets[8]={0,-1,-SX,-SX-1,-SLICE,-SLICE-1,-SLICE-SX,-SLICE-SX-1};
  for(int i=0;i<count;++i)if(active[i]){
   Vector3 p=positions[i],c=(p-origin)/cell;
   for(int y=std::max(1,int(std::floor(c.y))-2);y<std::min(SY-1,int(std::ceil(c.y))+3);++y){
    float wy=origin.y+y*cell,dy=wy-p.y;if(dy*dy>=radius2)continue;
    for(int z=std::max(1,int(std::floor(c.z))-2);z<std::min(SZ-1,int(std::ceil(c.z))+3);++z){
     float dz=origin.z+z*cell-p.z,yz2=dy*dy+dz*dz;if(yz2>=radius2)continue;
     for(int x=std::max(1,int(std::floor(c.x))-2);x<std::min(SX-1,int(std::ceil(c.x))+3);++x){
      int plane=z*SX+x;if(wy<surface_floor[plane]+.002f)continue;
      float dx=origin.x+x*cell-p.x,q=1-(dx*dx+yz2)/radius2;if(q<=0)continue;
      int index=y*SLICE+plane;if(surface_field[index]==0)surface_touched.push_back(index);
      surface_field[index]+=q*q*q;surface_gradient[index]+=Vector3(dx,dy,dz)*(-6*q*q/radius2);
      for(int offset:offsets){int cindex=index+offset;if(!surface_flags[cindex]){surface_flags[cindex]=1;surface_cells.push_back(cindex);}}
     }
    }
   }
  }
  const int corners[8]={0,1,SX+1,SX,SLICE,SLICE+1,SLICE+SX+1,SLICE+SX};
  const int tets[6][4]={{0,5,1,6},{0,1,2,6},{0,2,3,6},{0,3,7,6},{0,7,4,6},{0,4,5,6}};
  const int edges[6][2]={{0,1},{1,2},{2,0},{0,3},{1,3},{2,3}};
  const int triangles[16][7]={{-1},{0,3,2,-1},{0,1,4,-1},{1,4,2,2,4,3,-1},{1,2,5,-1},{0,3,5,0,5,1,-1},{0,2,5,0,5,4,-1},{5,4,3,-1},{3,4,5,-1},{4,5,0,5,2,0,-1},{1,5,0,5,3,0,-1},{5,2,1,-1},{3,4,2,2,4,1,-1},{4,1,0,-1},{2,3,0,-1},{-1}};
  float values[8];Vector3 points[8],normals[8],ep[6],en[6];
  for(int index:surface_cells){
   int mask=0;for(int k=0;k<8;++k){values[k]=surface_field[index+corners[k]];if(values[k]>=iso)mask|=1<<k;}if(mask==0 || mask==255)continue;
   for(int k=0;k<8;++k){int n=index+corners[k],plane=n%SLICE;points[k]=origin+Vector3(plane%SX,n/SLICE,plane/SX)*cell;normals[k]=-surface_gradient[n];}
   for(const auto &tet:tets){
    int tm=0;for(int k=0;k<4;++k)if(values[tet[k]]>=iso)tm|=1<<k;const int *tris=triangles[tm];if(tris[0]<0)continue;
    for(int e=0;e<6;++e){int a=tet[edges[e][0]],b=tet[edges[e][1]];if((values[a]>=iso)==(values[b]>=iso))continue;float t=clampf((iso-values[a])/(values[b]-values[a]),0,1);ep[e]=points[a].lerp(points[b],t);Vector3 n=normals[a].lerp(normals[b],t);en[e]=n.length_squared()>1e-6f?n.normalized():Vector3(0,1,0);}
    for(int t=0;tris[t]>=0;t+=3){int a=tris[t],b=tris[t+1],c=tris[t+2];if((ep[b]-ep[a]).cross(ep[c]-ep[a]).dot(en[a]+en[b]+en[c])>0)std::swap(b,c);for(int v:{a,b,c}){surface_vertices.push_back(ep[v]);surface_normals.push_back(en[v]);}}
   }
  }
  PackedVector3Array vertices,normals_out;vertices.resize(surface_vertices.size());normals_out.resize(surface_normals.size());
  if(!surface_vertices.empty()){std::copy(surface_vertices.begin(),surface_vertices.end(),vertices.ptrw());std::copy(surface_normals.begin(),surface_normals.end(),normals_out.ptrw());}
  Dictionary result;result["vertices"]=vertices;result["normals"]=normals_out;return result;
 }

protected:
 static void _bind_methods(){
  ClassDB::bind_method(D_METHOD("configure","configuration"),&NativeLiquidSolver::configure);
  ClassDB::bind_method(D_METHOD("reset"),&NativeLiquidSolver::reset);
  ClassDB::bind_method(D_METHOD("step","delta","tilt"),&NativeLiquidSolver::step);
  ClassDB::bind_method(D_METHOD("get_state"),&NativeLiquidSolver::get_state);
  ClassDB::bind_method(D_METHOD("build_surface"),&NativeLiquidSolver::build_surface);
  ClassDB::bind_method(D_METHOD("set_particle_state","index","position","velocity"),&NativeLiquidSolver::set_particle_state);
 }
public:
 Dictionary build_surface(){return make_surface();}
 void configure(const Dictionary &cfg){
  floors.clear();elevations.clear();walls.clear();tiles.clear();
  Array input=cfg["regions"];PackedFloat32Array heights=cfg["elevations"];
  for(int i=0;i<input.size();++i){floors.push_back(Rect2(input[i]));elevations.push_back(i<heights.size()?heights[i]:0);}
  Array ws=cfg["walls"];for(int i=0;i<ws.size();++i){PackedFloat32Array w=ws[i];std::array<float,6> a{};for(int k=0;k<6;++k)a[k]=w[k];walls.push_back(a);}
  Array ts=cfg["tiles"];for(int i=0;i<ts.size();++i){Dictionary t=ts[i];tiles.push_back(TerrainTile{Rect2(t["bounds"]),float(t["height"])});}
  bounds=cfg["bounds"];spawn=cfg["spawn"];goal=cfg["goal"];
  count=int(cfg["count"]);top=float(cfg["top"]);base=float(cfg["base"]);radius=float(cfg["radius"]);spacing=float(cfg["spacing"]);h=float(cfg["h"]);rho=float(cfg["rho"]);
  drag=float(cfg["drag"]);max_speed=float(cfg["max_speed"]);viscosity=float(cfg["viscosity"]);iterations=int(cfg["iterations"]);required=float(cfg["required"]);hold_seconds=float(cfg["hold"]);
  ERR_FAIL_COND(count<1 || count>4096 || floors.empty() || h<=0 || rho<=0);
  float integral=0;wall_table[0]=0;
  for(int i=1;i<=64;++i){float a=float(i-1)/64,b=float(i)/64;integral+=(std::pow(1-a*a,4.f)+std::pow(1-b*b,4.f))/128;wall_table[i]=integral;}
  for(auto &v:wall_table)v=.5f+v/integral*.5f;
  reset();
 }
 void reset(){
  positions.assign(count,Vector3());velocities.assign(count,Vector3());previous.resize(count);corrections.resize(count);contacts.resize(count);smoothed.resize(count);boundary_gradient.resize(count);
  lambdas.resize(count);densities.resize(count);inverse_density.resize(count);active.assign(count,1);neighbors.resize(count);
  int columns=std::max(1,int(std::floor((spawn.size.x-.2f)/spacing))),rows=std::max(1,int(std::floor((spawn.size.y-.2f)/spacing)));
  for(int i=0;i<count;++i){int column=i%columns,row=(i/columns)%rows,layer=i/(columns*rows);Vector2 xz=spawn.position+Vector2(.1f+column*spacing+(row%2)*spacing*.25f,.1f+row*spacing);positions[i]=Vector3(xz.x,floor_height(xz)+radius+.02f+layer*spacing,xz.y);neighbors[i].reserve(64);}
  lost=0;fraction=0;held=0;completed=false;
 }
 void step(double delta,Vector2 tilt){
  if(completed || delta<=0 || count<=0)return;
  double duration=std::min(delta,1./30.);int steps=std::max(1,int(std::ceil(duration*60.-1e-7)));float dt=float(duration/steps);
  if(tilt.length_squared()>1)tilt=tilt.normalized();tilt*=.7f;Vector3 gravity=Vector3(tilt.x,-1,tilt.y).normalized()*9.81f;
  for(int i=0;i<steps;++i)substep(dt,gravity);
  int delivered=0;for(int i=0;i<count;++i)if(active[i]){auto p=positions[i];Vector2 xz(p.x,p.z);if(goal.has_point(xz) && p.y<floor_height(xz)+.34f)++delivered;}
  fraction=float(delivered)/count;held=fraction>=required?held+float(duration):0;completed=held>=hold_seconds;
 }
 Dictionary get_state() const {
  PackedVector3Array p,v;p.resize(count);v.resize(count);PackedByteArray a;a.resize(count);
  for(int i=0;i<count;++i){p.set(i,positions[i]);v.set(i,velocities[i]);a.set(i,active[i]);}
  Dictionary d;d["positions"]=p;d["velocities"]=v;d["active"]=a;d["lost"]=lost;d["fraction"]=fraction;d["held"]=held;d["completed"]=completed;return d;
 }
 void set_particle_state(int i,Vector3 p,Vector3 v){ERR_FAIL_INDEX(i,count);positions[i]=p;velocities[i]=v;if(!active[i]){active[i]=1;--lost;}}
};

void initialize_hydrologic(ModuleInitializationLevel level){if(level==MODULE_INITIALIZATION_LEVEL_SCENE)ClassDB::register_class<NativeLiquidSolver>();}
void uninitialize_hydrologic(ModuleInitializationLevel){}
extern "C" {
GDExtensionBool GDE_EXPORT hydrologic_library_init(GDExtensionInterfaceGetProcAddress get_proc,GDExtensionClassLibraryPtr library,GDExtensionInitialization *initialization){
 GDExtensionBinding::InitObject object(get_proc,library,initialization);object.register_initializer(initialize_hydrologic);object.register_terminator(uninitialize_hydrologic);object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);return object.init();
}
}
