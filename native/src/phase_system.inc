// Members of NativeLiquidSolver. Water-equivalent parcel mass never changes
// during a phase transition. Heat is stored as specific enthalpy, including
// fusion and vaporization plateaus; only an actual exit removes a parcel.
enum Phase : uint8_t { LIQUID=0, ICE=1, VAPOR=2 };
static constexpr float CP_ICE=2100.f, CP_WATER=4180.f, CP_VAPOR=2010.f;
static constexpr float FUSION=334000.f, BOILING=FUSION+100*CP_WATER;
static constexpr float VAPORIZATION=2256000.f, STEAM=BOILING+VAPORIZATION;
struct HeatRegion { AABB bounds; float temperature,conductance; };
struct IceBody {
    std::vector<int> ids;
    std::vector<Vector3> rest,contacts;
    Vector3 centre,velocity,omega,low,high;
    Quaternion rotation;
    Basis inverse_inertia;
    float mass=0;
};
std::vector<uint8_t> phases;
std::vector<float> enthalpy;
std::vector<HeatRegion> heat_regions;
std::vector<IceBody> ice_bodies;
std::vector<int> ice_owner,dynamic_cells,ice_heads,ice_next,ice_spatial_cells;
std::vector<uint8_t> terrain_solid;
bool thermal=false,ice_dirty=false;
int initial_phase=LIQUID,goal_phase=LIQUID,surface_selected_phase=LIQUID;
float initial_temperature=20,thermal_time=0;
double environmental_heat=0;
bool impact_enabled=false,impact_latched=false,impact_contact=false,impact_released=false;
Vector3 impact_hinge;
Basis impact_frame;
float impact_width=1.2f,impact_height=.7f,impact_thickness=.06f;
float impact_angle=0,impact_omega=0,impact_load=0;
float impact_inertia=5,impact_spring=20,impact_damping=10,impact_detent=45;

float parcel_mass() const { return mass_density*spacing*spacing*spacing; }
static float temperature_of(float e) {
    if (e<0) return e/CP_ICE;
    if (e<FUSION) return 0;
    if (e<BOILING) return (e-FUSION)/CP_WATER;
    if (e<STEAM) return 100;
    return 100+(e-STEAM)/CP_VAPOR;
}
static float equilibrium_enthalpy(float t) {
    return t<0 ? CP_ICE*t : (t>100 ? STEAM+CP_VAPOR*(t-100) : FUSION+CP_WATER*t);
}
void configure_phases(const Dictionary &cfg) {
    heat_regions.clear();
    if (cfg.has("heat_regions")) {
        Array list=cfg["heat_regions"];
        for (int i=0;i<list.size();++i) {
            Dictionary h=list[i];
            heat_regions.push_back({AABB(h["bounds"]),float(h["temperature"]),float(h["conductance"])});
        }
    }
    initial_phase=cfg.has("initial_phase") ? int(cfg["initial_phase"]) : LIQUID;
    initial_temperature=cfg.has("initial_temperature") ? float(cfg["initial_temperature"]) : 20;
    goal_phase=cfg.has("goal_phase") ? int(cfg["goal_phase"]) : LIQUID;
    thermal=!heat_regions.empty() || initial_phase!=LIQUID;
    Dictionary gate=cfg.has("impact_gate") ? Dictionary(cfg["impact_gate"]) : Dictionary();
    impact_enabled=!gate.is_empty();
    if (impact_enabled) {
        impact_hinge=gate["hinge"]; Vector2 forward=gate.get("direction",Vector2(0,1));
        forward.normalize();
        impact_frame=Basis(Vector3(forward.y,0,-forward.x),Vector3(0,1,0),Vector3(forward.x,0,forward.y));
        impact_width=gate.get("width",1.2f); impact_height=gate.get("height",.7f);
        impact_thickness=gate.get("thickness",.06f); impact_inertia=gate.get("inertia",5.f);
        impact_spring=gate.get("spring",20.f); impact_damping=gate.get("damping",10.f);
        impact_detent=gate.get("detent",45.f);
    }
}
static int64_t thermal_key(int x,int y,int z) {
    return int64_t(x+16384)*1099511627776LL+int64_t(y+16384)*1048576LL+z+16384;
}
void update_phase(int i) {
    uint8_t before=phases[i]; float e=enthalpy[i];
    if (before==ICE && e>=FUSION) phases[i]=LIQUID;
    else if (before==LIQUID && e<0) phases[i]=ICE;
    else if (before==LIQUID && e>=STEAM) phases[i]=VAPOR;
    else if (before==VAPOR && e<=BOILING) phases[i]=LIQUID;
    if (before!=phases[i] && phases[i]==ICE) {
        float floor=floor_height(Vector2(positions[i].x,positions[i].z));
        if (std::isfinite(floor)) positions[i].y=floor+radius+std::max(0.f,positions[i].y-floor-radius)*(1000.f/917.f);
    }
    if (before!=phases[i] && (before==ICE || phases[i]==ICE)) ice_dirty=true;
    if (before!=phases[i] && captured[i] && phases[i]!=goal_phase) { captured[i]=0; --secured; }
}
void advance_temperature(float dt) {
    if (!thermal) return;
    thermal_time+=dt;
    for (int i=0;i<count;++i) if (active[i]) {
        for (const auto &h:heat_regions) if (h.bounds.has_point(positions[i])) {
            float t=temperature_of(enthalpy[i]);
            float target=equilibrium_enthalpy(h.temperature);
            float next=enthalpy[i]+h.conductance*(h.temperature-t)*dt;
            next=h.temperature>=t ? std::min(next,target) : std::max(next,target);
            environmental_heat+=double(next-enthalpy[i])*parcel_mass(); enthalpy[i]=next;
        }
    }
    // Symmetric conduction between touching parcels conserves total energy.
    float h=spacing*1.7f,h2=h*h;
    std::unordered_map<int64_t,std::vector<int>> bins;
    for (int i=0;i<count;++i) if (active[i] && phases[i]!=VAPOR) {
        Vector3 p=positions[i]/h;
        bins[thermal_key(int(std::floor(p.x)),int(std::floor(p.y)),int(std::floor(p.z)))].push_back(i);
    }
    for (int i=0;i<count;++i) if (active[i] && phases[i]!=VAPOR) {
        Vector3 q=positions[i]/h; int x=int(std::floor(q.x)),y=int(std::floor(q.y)),z=int(std::floor(q.z));
        for (int dy=-1;dy<=1;++dy) for (int dz=-1;dz<=1;++dz) for (int dx=-1;dx<=1;++dx) {
            auto found=bins.find(thermal_key(x+dx,y+dy,z+dz)); if (found==bins.end()) continue;
            for (int j:found->second) if (j>i && positions[i].distance_squared_to(positions[j])<h2) {
                float difference=temperature_of(enthalpy[j])-temperature_of(enthalpy[i]);
                float exchange=std::copysign(std::min(std::abs(difference)*40*dt,std::abs(difference)*CP_ICE*.025f),difference);
                enthalpy[i]+=exchange; enthalpy[j]-=exchange;
            }
        }
    }
    for (int i=0;i<count;++i) if (active[i]) update_phase(i);
    if (ice_dirty) rebuild_ice();
}
void rebuild_ice() {
    ice_bodies.clear(); ice_owner.assign(count,-1); ice_dirty=false;
    float h=spacing*2.8f,h2=h*h;
    std::vector<int> parent(count); std::iota(parent.begin(),parent.end(),0);
    auto root_of=[&](int i) { while (parent[i]!=i) { parent[i]=parent[parent[i]]; i=parent[i]; } return i; };
    std::unordered_map<int64_t,std::vector<int>> bins;
    for (int i=0;i<count;++i) if (active[i] && phases[i]==ICE) {
        Vector3 p=positions[i]/h; int x=int(std::floor(p.x)),y=int(std::floor(p.y)),z=int(std::floor(p.z));
        for (int dy=-1;dy<=1;++dy) for (int dz=-1;dz<=1;++dz) for (int dx=-1;dx<=1;++dx) {
            auto found=bins.find(thermal_key(x+dx,y+dy,z+dz)); if (found==bins.end()) continue;
            for (int j:found->second) if (captured[i]==captured[j] && positions[i].distance_squared_to(positions[j])<h2) {
                Vector3 mid=(positions[i]+positions[j])*.5f;
                if (mid.y<floor_height(Vector2(mid.x,mid.z))-radius) continue;
                parent[root_of(i)]=root_of(j);
            }
        }
        bins[thermal_key(x,y,z)].push_back(i);
    }
    std::unordered_map<int,int> groups;
    for (int i=0;i<count;++i) if (active[i] && phases[i]==ICE) {
        int root=root_of(i);
        if (!groups.count(root)) { groups[root]=int(ice_bodies.size()); ice_bodies.push_back(IceBody()); }
        int owner=groups[root]; ice_owner[i]=owner; ice_bodies[owner].ids.push_back(i);
    }
    for (auto &b:ice_bodies) {
        for (int i:b.ids) { b.centre+=positions[i]; b.velocity+=velocities[i]; }
        b.centre/=float(b.ids.size()); b.velocity/=float(b.ids.size());
        b.mass=float(b.ids.size())*parcel_mass(); b.low=Vector3(1e6f,1e6f,1e6f); b.high=-b.low;
        float xx=0,yy=0,zz=0,xy=0,xz=0,yz=0; Vector3 angular;
        for (int i:b.ids) {
            Vector3 r=positions[i]-b.centre; b.rest.push_back(r); b.low=b.low.min(r); b.high=b.high.max(r);
            xx+=r.y*r.y+r.z*r.z; yy+=r.x*r.x+r.z*r.z; zz+=r.x*r.x+r.y*r.y;
            xy-=r.x*r.y; xz-=r.x*r.z; yz-=r.y*r.z;
            angular+=r.cross(velocities[i]-b.velocity)*parcel_mass();
        }
        float stabilizer=float(b.ids.size())*spacing*spacing*.2f;
        Basis inertia=Basis(xx+stabilizer,xy,xz,xy,yy+stabilizer,yz,xz,yz,zz+stabilizer)*parcel_mass();
        b.inverse_inertia=inertia.inverse(); b.omega=limited(b.inverse_inertia.xform(angular),4);
        for (int k=0;k<8;++k) {
            Vector3 corner(k&1 ? b.high.x:b.low.x,k&2 ? b.high.y:b.low.y,k&4 ? b.high.z:b.low.z);
            float best=1e20f; Vector3 point;
            for (const auto &r:b.rest) if (r.distance_squared_to(corner)<best) { best=r.distance_squared_to(corner); point=r; }
            b.contacts.push_back(point);
        }
        for (int k=0;k<std::min(256,int(b.rest.size()));++k) b.contacts.push_back(b.rest[(k*1543)%b.rest.size()]);
    }
}
Basis ice_world_inverse(const IceBody &b) const {
    Basis r(b.rotation); return r*b.inverse_inertia*r.transposed();
}
Vector3 constrain_ramps(Vector3 point,float r) const {
    for (const auto &ramp:ramps) if (ramp.bounds.has_point(Vector2(point.x,point.z))) {
        Vector3 n=Vector3(-ramp.gradient.x,1,-ramp.gradient.y).normalized();
        float distance=(point.y-ramp.sample(Vector2(point.x,point.z)))*n.y;
        if (distance<r && point.y>base-r) point+=n*(r-distance);
    }
    return point;
}
Basis impact_rotation() const { return impact_frame*Basis(Vector3(1,0,0),-impact_angle); }
Vector3 constrain_impact(Vector3 point,float r) const {
    if (!impact_enabled) return point;
    Basis frame=impact_rotation(); Vector3 local=frame.transposed().xform(point-impact_hinge);
    local=collide_box(local,Vector3(-impact_width*.5f,-impact_height,-impact_thickness*.5f),Vector3(impact_width*.5f,0,impact_thickness*.5f),r);
    return impact_hinge+frame.xform(local);
}
bool impact_contains(Vector3 p) const {
    if (!impact_enabled) return false;
    Vector3 q=impact_rotation().transposed().xform(p-impact_hinge);
    return std::abs(q.x)<impact_width*.5f && q.y<0 && q.y>-impact_height && std::abs(q.z)<impact_thickness*.5f;
}
void update_impact(float dt) {
    if (!impact_enabled) return;
    if (impact_latched) { impact_angle=1.52f; impact_omega=0; return; }
    float torque=0; impact_contact=false;
    for (int i=0;i<count;++i) if (active[i] && phases[i]==LIQUID) {
        Vector3 p=impact_frame.transposed().xform(positions[i]-impact_hinge);
        if (std::abs(p.x)>impact_width*.5f || p.y>0 || p.y<-impact_height || p.z>0 || p.z<-.6f) continue;
        Vector3 v=impact_frame.transposed().xform(velocities[i]);
        torque+=parcel_mass()*std::max(v.z,0.f)*std::max(v.z,0.f)/.6f*std::max(-p.y,0.f);
        if (p.z>-.13f) impact_contact=true;
    }
    if (!impact_contact) torque=0;
    impact_load=torque/std::max(impact_detent,.001f);
    if (!impact_released && torque<impact_detent) { impact_omega=impact_angle=0; return; }
    impact_released=true;
    float spring=impact_angle>.32f ? impact_spring*(1.52f-impact_angle) : -impact_spring*impact_angle;
    impact_omega+=(torque+spring-impact_damping*impact_omega)/impact_inertia*dt;
    impact_omega=clampf(impact_omega,-3,5);
    impact_angle=clampf(impact_angle+impact_omega*dt,0,1.52f);
    if (impact_angle<=0 && impact_omega<0) { impact_released=false; impact_omega=0; }
    if (impact_angle>1.30f) { impact_latched=true; impact_angle=1.52f; }
}
void mark_dynamic_box(const Basis &frame,Vector3 centre,Vector3 low,Vector3 high) {
    Vector3 minimum(1e6f,1e6f,1e6f),maximum=-minimum;
    for (int k=0;k<8;++k) {
        Vector3 p=centre+frame.xform(Vector3(k&1 ? high.x:low.x,k&2 ? high.y:low.y,k&4 ? high.z:low.z));
        minimum=minimum.min(p); maximum=maximum.max(p);
    }
    Vector3 lo=(minimum-origin)/cell_size,hi=(maximum-origin)/cell_size;
    for (int y=std::max(1,int(std::floor(lo.y)));y<=std::min(ny-2,int(std::ceil(hi.y)));++y)
    for (int z=std::max(1,int(std::floor(lo.z)));z<=std::min(nz-2,int(std::ceil(hi.z)));++z)
    for (int x=std::max(1,int(std::floor(lo.x)));x<=std::min(nx-2,int(std::ceil(hi.x)));++x) {
        Vector3 p=frame.transposed().xform(origin+Vector3(x+.5f,y+.5f,z+.5f)*cell_size-centre);
        if (p.x<low.x || p.y<low.y || p.z<low.z || p.x>high.x || p.y>high.y || p.z>high.z) continue;
        int i=index(x,y,z); if (!solid[i]) { solid[i]=1; dynamic_cells.push_back(i); }
    }
}
void rebuild_ice_bins() {
    if (ice_heads.size()!=size_t(total)) ice_heads.assign(total,-1);
    for (int i:ice_spatial_cells) ice_heads[i]=-1;
    ice_spatial_cells.clear(); ice_next.resize(count);
    for (int i=0;i<count;++i) if (active[i] && phases[i]==ICE) {
        Vector3 q=(positions[i]-origin)/cell_size;
        int x=int(std::floor(q.x)),y=int(std::floor(q.y)),z=int(std::floor(q.z));
        if (!in_grid(x,y,z)) continue;
        int cell=index(x,y,z); if (ice_heads[cell]<0) ice_spatial_cells.push_back(cell);
        ice_next[i]=ice_heads[cell]; ice_heads[cell]=i;
    }
}
void refresh_dynamic_solids() {
    if (dynamic_cells.empty() && !impact_enabled && ice_bodies.empty()) return;
    for (int i:dynamic_cells) solid[i]=terrain_solid[i]; dynamic_cells.clear();
    if (impact_enabled) mark_dynamic_box(impact_rotation(),impact_hinge,Vector3(-impact_width*.5f,-impact_height,-impact_thickness*.5f),Vector3(impact_width*.5f,0,impact_thickness*.5f));
    if (ice_bodies.empty()) return;
    rebuild_ice_bins();
    float r=spacing*1.05f,r2=r*r;
    for (int i=0;i<count;++i) if (active[i] && phases[i]==ICE) {
        Vector3 q=(positions[i]-origin)/cell_size;
        int cx=int(std::floor(q.x)),cy=int(std::floor(q.y)),cz=int(std::floor(q.z));
        for (int dy=-1;dy<=1;++dy) for (int dz=-1;dz<=1;++dz) for (int dx=-1;dx<=1;++dx) {
            int x=cx+dx,y=cy+dy,z=cz+dz; if (!in_grid(x,y,z)) continue;
            Vector3 p=origin+Vector3(x+.5f,y+.5f,z+.5f)*cell_size;
            if (p.distance_squared_to(positions[i])>r2) continue;
            int cell=index(x,y,z); if (!solid[cell]) { solid[cell]=1; dynamic_cells.push_back(cell); }
        }
    }
}
void retain_ice(IceBody &b) {
    if (!safe_goal || b.ids.empty() || !captured[b.ids[0]]) return;
    Vector3 low(1e6f,1e6f,1e6f),high=-low;
    for (const auto &r:b.rest) { Vector3 p=b.centre+b.rotation.xform(r); low=low.min(p); high=high.max(p); }
    Vector3 shift;
    if (low.x<goal.position.x+radius) shift.x=goal.position.x+radius-low.x;
    if (high.x>goal.get_end().x-radius) shift.x=goal.get_end().x-radius-high.x;
    if (low.z<goal.position.y+radius) shift.z=goal.position.y+radius-low.z;
    if (high.z>goal.get_end().y-radius) shift.z=goal.get_end().y-radius-high.z;
    float floor=floor_height(goal.get_center());
    if (low.y<floor+radius) shift.y=floor+radius-low.y;
    if (high.y>top-radius) shift.y=top-radius-high.y;
    b.centre+=shift;
    if (shift.x*b.velocity.x<0) b.velocity.x=0;
    if (shift.y*b.velocity.y<0) b.velocity.y=0;
    if (shift.z*b.velocity.z<0) b.velocity.z=0;
}
void advance_ice(float dt,Vector3 gravity) {
    if (ice_dirty) rebuild_ice();
    if (ice_bodies.empty()) return;
    std::unordered_map<int64_t,float> water_tops;
    for (int i=0;i<count;++i) if (active[i] && phases[i]==LIQUID) {
        int x=int(std::floor(positions[i].x/cell_size)),z=int(std::floor(positions[i].z/cell_size));
        int64_t key=thermal_key(x,0,z); auto found=water_tops.find(key);
        if (found==water_tops.end()) water_tops[key]=positions[i].y; else found->second=std::max(found->second,positions[i].y);
    }
    for (auto &b:ice_bodies) {
        Vector3 old=b.centre; Quaternion old_rotation=b.rotation;
        int submerged=0;
        for (int id:b.ids) {
            int x=int(std::floor(positions[id].x/cell_size)),z=int(std::floor(positions[id].z/cell_size));
            float level=-1e6f;
            for (int dx=-1;dx<=1;++dx) for (int dz=-1;dz<=1;++dz) {
                auto found=water_tops.find(thermal_key(x+dx,0,z+dz));
                if (found!=water_tops.end()) level=std::max(level,found->second);
            }
            if (positions[id].y<level) ++submerged;
        }
        float displaced=float(submerged)/b.ids.size();
        b.velocity=limited((b.velocity+gravity*(1.f-displaced*1000.f/917.f)*dt)*std::exp(-.035f*dt),max_speed);
        b.omega*=std::exp(-.25f*dt); b.centre+=b.velocity*dt;
        float angular_speed=b.omega.length();
        if (angular_speed>1e-6f) b.rotation=(Quaternion(b.omega/angular_speed,angular_speed*dt)*b.rotation).normalized();
        Basis inverse=ice_world_inverse(b);
        for (int pass=0;pass<3;++pass) for (const auto &r:b.contacts) {
            Vector3 arm=b.rotation.xform(r),p=b.centre+arm;
            Vector3 previous=old+old_rotation.xform(r),resolved=constrain(p,previous),correction=resolved-p;
            if (correction.length_squared()<1e-12f) continue;
            Vector3 n=correction.normalized(); b.centre+=correction*.8f;
            Vector3 velocity=b.velocity+b.omega.cross(arm); float vn=velocity.dot(n);
            if (vn<0) {
                float denominator=1.f/b.mass+n.dot(inverse.xform(arm.cross(n)).cross(arm));
                float j=-vn/std::max(denominator,1e-6f);
                Vector3 tangent=velocity-n*vn;
                Vector3 impulse=n*j;
                if (tangent.length_squared()>1e-10f) impulse-=tangent.normalized()*std::min(tangent.length()/std::max(denominator,1e-6f),j*.06f);
                b.velocity+=impulse/b.mass; b.omega+=inverse.xform(arm.cross(impulse)); b.omega=limited(b.omega,4);
            }
        }
        Vector3 low(1e6f,1e6f,1e6f),high=-low;
        for (const auto &r:b.rest) { Vector3 p=b.centre+b.rotation.xform(r); low=low.min(p); high=high.max(p); }
        bool inside=low.x>=goal.position.x+radius-.003f && high.x<=goal.get_end().x-radius+.003f && low.z>=goal.position.y+radius-.003f && high.z<=goal.get_end().y-radius+.003f && high.y<top;
        if (safe_goal && goal_phase==ICE && inside) for (int id:b.ids) if (!captured[id]) { captured[id]=1; ++secured; }
        retain_ice(b);
        for (size_t k=0;k<b.ids.size();++k) {
            int id=b.ids[k]; Vector3 arm=b.rotation.xform(b.rest[k]); positions[id]=b.centre+arm; velocities[id]=b.velocity+b.omega.cross(arm);
        }
    }
}
template<class Visit> void visit_ice(Vector3 point,Visit visit) const {
    if (ice_bodies.empty() || ice_heads.empty()) return;
    Vector3 q=(point-origin)/cell_size;
    int cx=int(std::floor(q.x)),cy=int(std::floor(q.y)),cz=int(std::floor(q.z));
    for (int dy=-1;dy<=1;++dy) for (int dz=-1;dz<=1;++dz) for (int dx=-1;dx<=1;++dx) {
        int x=cx+dx,y=cy+dy,z=cz+dz; if (!in_grid(x,y,z)) continue;
        for (int j=ice_heads[index(x,y,z)];j>=0;j=ice_next[j]) if (active[j] && phases[j]==ICE) visit(j);
    }
}
Vector3 project_ice(Vector3 point,float r) const {
    float extent=spacing*.65f+r;
    visit_ice(point,[&](int j) {
        Vector3 delta=point-positions[j]; float d=delta.length();
        if (d<extent) point+=(d>1e-6f ? delta/d:Vector3(0,1,0))*(extent-d);
    });
    return point;
}
bool ice_contains(Vector3 point) const {
    bool inside=false; float r=spacing*.65f;
    visit_ice(point,[&](int j) { if (point.distance_squared_to(positions[j])<r*r) inside=true; });
    return inside;
}
void collide_ice(Vector3 &point,Vector3 &velocity) {
    if (ice_bodies.empty()) return;
    float extent=spacing*.65f+radius;
    for (int pass=0;pass<3;++pass) visit_ice(point,[&](int j) {
        int owner=ice_owner[j]; if (owner<0) return;
        IceBody &b=ice_bodies[owner];
        Vector3 difference=point-positions[j]; float d=difference.length();
        if (d>=extent) return;
        Vector3 normal=d>1e-6f ? difference/d:Vector3(0,1,0);
        Vector3 candidate=point+normal*(extent-d);
        candidate=constrain(candidate,point);
        Vector3 correction=candidate-point;
        if (correction.length_squared()<1e-12f) return;
        point=candidate; normal=correction.normalized(); Vector3 arm=point-b.centre;
        float speed=(velocity-b.velocity-b.omega.cross(arm)).dot(normal);
        if (speed>=0) return;
        Basis inverse=ice_world_inverse(b);
        float denominator=1.f/parcel_mass()+1.f/b.mass+normal.dot(inverse.xform(arm.cross(normal)).cross(arm));
        Vector3 impulse=normal*(-speed/denominator);
        velocity+=impulse/parcel_mass(); b.velocity-=impulse/b.mass; b.omega-=inverse.xform(arm.cross(impulse));
    });
}
void collide_ice_bodies() {
    if (ice_bodies.size()<2) return;
    struct Contact { int a,b; Vector3 point,normal; float depth; };
    std::unordered_map<int64_t,Contact> contacts; float extent=spacing*1.3f;
    for (int i=0;i<count;++i) if (active[i] && phases[i]==ICE) visit_ice(positions[i],[&](int j) {
        if (j<=i || ice_owner[i]==ice_owner[j]) return;
        Vector3 difference=positions[j]-positions[i]; float d=difference.length();
        if (d>=extent || d<1e-6f) return;
        int a=ice_owner[i],b=ice_owner[j]; if (a<0 || b<0) return;
        int64_t key=int64_t(std::min(a,b))*ice_bodies.size()+std::max(a,b);
        float depth=extent-d;
        auto previous=contacts.find(key);
        if (previous==contacts.end() || previous->second.depth<depth) contacts[key]={a,b,(positions[i]+positions[j])*.5f,difference/d,depth};
    });
    for (const auto &entry:contacts) {
        const Contact &c=entry.second; IceBody &a=ice_bodies[c.a],&b=ice_bodies[c.b];
        float inverse_mass=1.f/a.mass+1.f/b.mass;
        a.centre-=c.normal*(c.depth/a.mass/inverse_mass*.8f); b.centre+=c.normal*(c.depth/b.mass/inverse_mass*.8f);
        Vector3 ra=c.point-a.centre,rb=c.point-b.centre;
        float closing=(b.velocity+b.omega.cross(rb)-a.velocity-a.omega.cross(ra)).dot(c.normal);
        if (closing>=0) continue;
        Basis ia=ice_world_inverse(a),ib=ice_world_inverse(b);
        float denominator=inverse_mass+c.normal.dot(ia.xform(ra.cross(c.normal)).cross(ra)+ib.xform(rb.cross(c.normal)).cross(rb));
        Vector3 impulse=c.normal*(-closing/std::max(denominator,1e-6f));
        a.velocity-=impulse/a.mass; b.velocity+=impulse/b.mass;
        a.omega-=ia.xform(ra.cross(impulse)); b.omega+=ib.xform(rb.cross(impulse));
    }
}
void mark_lost(int i,int reason) {
    if (!active[i]) return;
    active[i]=0; ++lost; loss_reason[i]=reason;
    if (reason==2) ++lost_in_void;
    if (reason==3) ++lost_without_rim;
    if (captured[i]) { captured[i]=0; --secured; }
}
void record_loss(int i,Vector3 previous,Vector3 candidate) {
    Vector3 point=positions[i]; Vector2 xz(point.x,point.z);
    float supporting_floor=floor_height(xz);
    if (is_void(xz)) through_void[i]=1;
    else if (std::isfinite(supporting_floor) && point.y>=supporting_floor+radius-.0001f) through_void[i]=0;
    if (std::max({previous.y,candidate.y,point.y})>=top-radius) over_rim[i]=1;
    if (!escaped[i] && !bounds.has_point(xz)) {
        escaped[i]=1;
        if (!over_rim[i] && bounds.has_point(Vector2(previous.x,previous.z))) {
            float t=1;
            if (point.x<bounds.position.x) t=std::min(t,(bounds.position.x-previous.x)/(point.x-previous.x));
            if (point.x>=bounds.get_end().x) t=std::min(t,(bounds.get_end().x-previous.x)/(point.x-previous.x));
            if (point.z<bounds.position.y) t=std::min(t,(bounds.position.y-previous.z)/(point.z-previous.z));
            if (point.z>=bounds.get_end().y) t=std::min(t,(bounds.get_end().y-previous.z)/(point.z-previous.z));
            Vector3 crossing=previous.lerp(point,clampf(t,0,1));
            Vector2 at(clampf(crossing.x,bounds.position.x+.001f,bounds.get_end().x-.001f),clampf(crossing.z,bounds.position.y+.001f,bounds.get_end().y-.001f));
            if (crossing.y>=floor_height(at)-radius) over_rim[i]=1;
        }
        bool nearby=false; for (auto p:spill_points) if (p.distance_squared_to(point)<.16f) nearby=true;
        if (!nearby && spill_points.size()<8) spill_points.push_back(point);
    }
    if (point.y<base-.65f || !bounds.grow(.42f).has_point(xz)) {
        int reason=through_void[i] ? 2 : (over_rim[i] ? 1:3); mark_lost(i,reason);
        if (reason==2 && spill_points.size()<8) spill_points.push_back(point);
    }
}
void advance_vapor(float dt,Vector3 gravity) {
    if (!thermal) return;
    for (int i=0;i<count;++i) if (active[i] && phases[i]==VAPOR) {
        Vector3 p=positions[i];
        Vector3 swirl(std::sin(p.z*3+thermal_time)*.22f,0,std::cos(p.x*3-thermal_time)*.22f);
        velocities[i]=limited((velocities[i]+(-gravity*.8f+swirl)*dt)*std::exp(-1.1f*dt),1.8f);
        Vector3 candidate=p+velocities[i]*dt,q=constrain(candidate,p);
        Vector3 correction=q-candidate;
        if (correction.length_squared()>1e-10f) { Vector3 n=correction.normalized(); float vn=velocities[i].dot(n); if (vn<0) velocities[i]-=n*vn; }
        positions[i]=q;
        if (q.y>top+1.f || !bounds.grow(.42f).has_point(Vector2(q.x,q.z))) mark_lost(i,4);
    }
}
void finish_ice_step() {
    collide_ice_bodies();
    for (auto &b:ice_bodies) {
        // Body-body contact may displace a retained block. Reapply the
        // container constraint to the whole rigid body before publishing it.
        retain_ice(b);
        bool gone=b.centre.y<base-.65f || !bounds.grow(.65f).has_point(Vector2(b.centre.x,b.centre.z));
        for (size_t k=0;k<b.ids.size();++k) {
            int id=b.ids[k]; if (!active[id]) continue;
            if (gone) { mark_lost(id,is_void(Vector2(b.centre.x,b.centre.z)) ? 2:1); ice_dirty=true; }
            else { Vector3 arm=b.rotation.xform(b.rest[k]); positions[id]=b.centre+arm; velocities[id]=b.velocity+b.omega.cross(arm); }
        }
    }
}
void reset_phases() {
    phases.assign(count,uint8_t(initial_phase)); enthalpy.assign(count,equilibrium_enthalpy(initial_temperature));
    if (initial_phase==ICE) {
        std::fill(enthalpy.begin(),enthalpy.end(),CP_ICE*std::min(initial_temperature,0.f));
        for (auto &p:positions) { float floor=floor_height(Vector2(p.x,p.z)); p.y=floor+radius+std::max(0.f,p.y-floor-radius)*(1000.f/917.f); }
    }
    ice_bodies.clear(); ice_owner.assign(count,-1); ice_dirty=initial_phase==ICE;
    for (int i:ice_spatial_cells) ice_heads[i]=-1; ice_spatial_cells.clear();
    impact_angle=impact_omega=impact_load=0; impact_latched=impact_contact=impact_released=false; thermal_time=0; environmental_heat=0;
    for (int i:dynamic_cells) solid[i]=terrain_solid[i]; dynamic_cells.clear();
    if (ice_dirty) rebuild_ice();
}
void append_phase_state(Dictionary &d) const {
    PackedByteArray state; state.resize(count);
    PackedFloat32Array temperatures; temperatures.resize(count);
    int water=0,ice=0,vapor=0,escaped_vapor=0,cold_count=0; double energy=0; float freeze_progress=0; bool intake=false;
    for (int i=0;i<count;++i) {
        state.set(i,phases[i]); temperatures.set(i,temperature_of(enthalpy[i]));
        energy+=double(enthalpy[i])*parcel_mass();
        if (!active[i]) { if (phases[i]==VAPOR) ++escaped_vapor; continue; }
        if (phases[i]==LIQUID) ++water; else if (phases[i]==ICE) ++ice; else ++vapor;
        for (const auto &h:heat_regions) if (h.temperature<0 && h.bounds.has_point(positions[i])) {
            freeze_progress+=clampf(1.f-std::max(enthalpy[i],0.f)/(FUSION+CP_WATER*20),0,1); ++cold_count; break;
        }
        Vector3 p=positions[i];
        if (safe_goal && phases[i]==goal_phase && velocities[i].z>.02f && p.x>goal.position.x && p.x<goal.get_end().x && p.z>goal.position.y-.7f && p.z<goal.position.y+.2f && p.y<top) intake=true;
    }
    d["phases"]=state; d["temperatures"]=temperatures;
    d["water_count"]=water; d["ice_count"]=ice; d["vapor_count"]=vapor; d["escaped_vapor"]=escaped_vapor;
    d["ice_bodies"]=int(ice_bodies.size()); d["enthalpy"]=energy; d["heat_input"]=environmental_heat;
    d["active_mass"]=double(count-lost)*parcel_mass(); d["lost_mass"]=double(lost)*parcel_mass();
    d["ice_volume"]=double(ice)*parcel_mass()/917.; d["physical_water_volume"]=double(water)*parcel_mass()/mass_density;
    d["impact_angle"]=impact_angle; d["impact_load"]=impact_load; d["impact_latched"]=impact_latched;
    d["intake_activity"]=intake; d["freeze_progress"]=cold_count>0 ? freeze_progress/cold_count:0.f;
}
