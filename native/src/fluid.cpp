// Hydrologic: incompressible 3D MAC / FLIP water with local capillary support.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <unordered_map>
#include <numeric>
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <vector>

using namespace godot;
namespace {
float clampf(float v, float a, float b) { return std::max(a, std::min(b, v)); }
Vector3 limited(Vector3 v, float maximum) {
    float squared = v.length_squared();
    return squared > maximum * maximum ? v * (maximum / std::sqrt(squared)) : v;
}
struct Tile { Rect2 rectangle; float height; };
struct RampPatch {
    Rect2 bounds; Vector2 gradient, origin; float height;
    float sample(Vector2 point) const { return height+(point-origin).dot(gradient); }
};
struct PolygonFloor { std::vector<Vector2> points; std::vector<std::vector<int>> scan_edges; Rect2 bounds; float height = 0; };
struct FaceGrid {
    std::vector<float> velocity, before, weight;
    std::vector<uint8_t> valid;
    std::vector<int> touched;
};
struct SealedSource {
    StringName id; Rect2 bounds; float floor=0, fill=0, opening=0, lower=0; std::vector<int> cells;
};
struct CapillaryPair { int a,b; Vector3 delta; float distance; };
}

class NativeLiquidSolver : public RefCounted {
    GDCLASS(NativeLiquidSolver, RefCounted)
    std::vector<Rect2> floors;
    std::vector<Rect2> voids;
    std::vector<PolygonFloor> polygons, openings;
    std::vector<float> elevations;
    std::vector<Tile> tiles;
    std::vector<AABB> obstacles;
    std::vector<RampPatch> ramps;
    // Exact terrain queries use a static broad phase. The final course has
    // many distant rooms; they must not all be tested for every parcel and
    // reconstructed vertex. Keep original shape order inside each bin.
    static constexpr float TERRAIN_BIN=.28f;
    int terrain_width=0,terrain_depth=0;
    std::vector<std::vector<int>> terrain_bins,contact_floor_bins;
    const std::vector<int> empty_terrain;
    std::vector<std::array<float, 6>> walls;
    std::vector<Vector3> wall_normals;
    std::vector<int> wall_indices, no_walls;
    std::vector<std::vector<int>> wall_bins;
    Rect2 bounds, reservoir, goal;
    float top = 1.05f, base = -.56f, spacing = .038f, radius = .017f;
    float cell_size = .07f, mass_density = 1000, viscosity = .000001f;
    float drag = .015f, max_speed = 3, flip_ratio = .95f;
    float surface_tension = .072f;
    float velocity_noise_limit = .40f;
    bool subgrid_capillarity = true;
    float cohesion_strength=3.f,cohesion_range=2.8f;
    float lowest_floor = 0;
    float required = .8f, hold_seconds = .75f, fraction = 0, held = 0, flow_speed = 1.15f;
    float maximum_divergence = 0, liquid_volume = 0;
    int count = 0, lost = 0, delivered = 0, lost_without_rim = 0, lost_in_void = 0, nx = 0, ny = 0, nz = 0, plane = 0, total = 0;
    int pressure_steps = 0;
    bool completed = false, reservoir_open = false, gate_controlled = false;
    bool curved = false;
    bool safe_goal = false;
    int secured = 0;
    float gate_fraction = 0, gate_lower = .42f;
    std::vector<SealedSource> sources;
    int collection_index=-1;
    std::vector<uint8_t> bank_captured;
    std::vector<int> initial_source;
    Vector3 origin;
    std::vector<Vector3> positions, velocities;
    std::vector<int> particle_heads,particle_next,particle_cells,support_count;
    std::vector<Vector3> capillary_impulse;
    std::vector<CapillaryPair> capillary_pairs;
    std::vector<Vector3> spill_points;
    std::vector<uint8_t> over_rim, escaped, through_void, loss_reason;
    std::vector<uint8_t> active, solid, vertical_wall;
    std::vector<uint8_t> captured, valve_closed;
    std::vector<int> valve_faces;
    std::vector<int> liquid_id, liquid_cells;
    std::vector<int> marker_count;
    std::vector<float> capillary_color;
    std::vector<Vector3> capillary_normal;
    std::vector<int> capillary_cells;
    std::vector<uint8_t> capillary_mark;
    std::array<FaceGrid, 3> faces;
    std::vector<float> pressure, rhs, residual, direction, preconditioned, product;
    std::vector<int> diagonal;
#include "phase_system.inc"

    int index(int x, int y, int z) const { return y * plane + z * nx + x; }
    bool in_grid(int x, int y, int z) const {
        return x >= 0 && y >= 0 && z >= 0 && x < nx && y < ny && z < nz;
    }
    bool is_solid(int x, int y, int z) const {
        return !in_grid(x, y, z) || solid[index(x, y, z)];
    }
    Vector3 mac_transfer_point(Vector3 point) const {
        Vector3 q=(point-origin)/cell_size;
        int x=int(std::floor(q.x)),y=int(std::floor(q.y)),z=int(std::floor(q.z));
        if (!in_grid(x,y,z) || !solid[index(x,y,z)]) return point;
        // Analytic walls need not align with voxel centres. A valid parcel
        // near a wall can sit in a voxel whose centre is solid. Dropping it
        // from pressure transfer made whole reservoirs fall ballistically
        // into a single corner. Use the nearest connected fluid stencil for
        // both scatter and gather, keeping the physical position untouched.
        float floor=floor_height(Vector2(point.x,point.z));
        if (std::isfinite(floor) && point.y<floor-.002f) return point;
        Vector3 best=point; float distance=cell_size*cell_size*4;
        for (int dy=-1;dy<=1;++dy) for (int dz=-1;dz<=1;++dz) for (int dx=-1;dx<=1;++dx) {
            int xx=x+dx,yy=y+dy,zz=z+dz;
            if (is_solid(xx,yy,zz)) continue;
            Vector3 candidate=origin+Vector3(xx+.5f,yy+.5f,zz+.5f)*cell_size;
            float d=candidate.distance_squared_to(point);
            if (d>=distance) continue;
            bool connected=true;
            for (const auto &source:sources) if (source.opening<.999f && source.bounds.has_point(Vector2(point.x,point.z)) && !source.bounds.has_point(Vector2(candidate.x,candidate.z))) connected=false;
            if (safe_goal && goal.has_point(Vector2(point.x,point.z)) && !goal.has_point(Vector2(candidate.x,candidate.z))) connected=false;
            Vector3 middle=(point+candidate)*.5f;
            if (impact_contains(middle) || (!ice_bodies.empty() && ice_contains(middle))) connected=false;
            if (!connected) continue;
            best=candidate; distance=d;
        }
        return best;
    }
    static PolygonFloor read_polygon(PackedVector2Array points, float height = 0) {
        PolygonFloor p; p.height = height;
        Vector2 low(1e10f,1e10f), high(-1e10f,-1e10f);
        for (int i=0;i<points.size();++i) {
            p.points.push_back(points[i]);
            low.x=std::min(low.x,points[i].x); low.y=std::min(low.y,points[i].y);
            high.x=std::max(high.x,points[i].x); high.y=std::max(high.y,points[i].y);
        }
        p.bounds=Rect2(low,high-low).grow(.00001f);
        p.scan_edges.resize(std::max(1,int(std::ceil(p.bounds.size.y/.14f))+1));
        for (size_t i=0,j=p.points.size()-1;i<p.points.size();j=i++) {
            int first=std::max(0,int(std::floor((std::min(p.points[i].y,p.points[j].y)-.00001f-p.bounds.position.y)/.14f)));
            int last=std::min(int(p.scan_edges.size())-1,int(std::floor((std::max(p.points[i].y,p.points[j].y)+.00001f-p.bounds.position.y)/.14f)));
            for (int k=first;k<=last;++k) p.scan_edges[k].push_back(int(i));
        }
        return p;
    }
    static bool inside_polygon(Vector2 point, const PolygonFloor &p) {
        if (!p.bounds.has_point(point)) return false;
        bool inside=false;
        int bucket=std::min(int(p.scan_edges.size())-1,std::max(0,int((point.y-p.bounds.position.y)/.14f)));
        for (int i:p.scan_edges[bucket]) {
            int j=(i+int(p.points.size())-1)%p.points.size();
            Vector2 a=p.points[i],b=p.points[j],v=b-a;
            if (point.x>=std::min(a.x,b.x)-1e-6f && point.x<=std::max(a.x,b.x)+1e-6f && point.y>=std::min(a.y,b.y)-1e-6f && point.y<=std::max(a.y,b.y)+1e-6f) {
                float cross=v.cross(point-a);
                if (cross*cross<1e-12f*std::max(v.length_squared(),1e-12f)) return true;
            }
            if ((a.y>point.y)!=(b.y>point.y) && point.x<(b.x-a.x)*(point.y-a.y)/(b.y-a.y)+a.x) inside=!inside;
        }
        return inside;
    }
    float floor_height(Vector2 point) const {
        if (!bounds.has_point(point)) return -std::numeric_limits<float>::infinity();
        float height = top;
        if (terrain_bins.empty()) {
            for (size_t i=0;i<floors.size();++i) if (floors[i].grow(.00001f).has_point(point)) height=std::min(height,elevations[i]);
            for (const auto &p:polygons) if (inside_polygon(point,p)) height=std::min(height,p.height);
            for (const auto &r:ramps) if (r.bounds.grow(.00001f).has_point(point)) height=std::min(height,r.sample(point));
        } else for (int id:terrain_bins[terrain_bin(point)]) {
            if (id<int(floors.size())) {
                if (floors[id].grow(.00001f).has_point(point)) height=std::min(height,elevations[id]);
            } else if (id<int(floors.size()+polygons.size())) {
                const auto &p=polygons[id-floors.size()];
                if (inside_polygon(point,p)) height=std::min(height,p.height);
            } else {
                const auto &r=ramps[id-floors.size()-polygons.size()];
                if (r.bounds.grow(.00001f).has_point(point)) height=std::min(height,r.sample(point));
            }
        }
        if (height==top) for (auto r:voids) if (r.has_point(point)) return -std::numeric_limits<float>::infinity();
        return height;
    }
    int terrain_bin(Vector2 point) const {
        int x=std::clamp(int(std::floor((point.x-bounds.position.x)/TERRAIN_BIN)),0,terrain_width-1);
        int z=std::clamp(int(std::floor((point.y-bounds.position.y)/TERRAIN_BIN)),0,terrain_depth-1);
        return z*terrain_width+x;
    }
    void build_terrain_index() {
        terrain_width=std::max(1,int(std::ceil(bounds.size.x/TERRAIN_BIN)));
        terrain_depth=std::max(1,int(std::ceil(bounds.size.y/TERRAIN_BIN)));
        terrain_bins.assign(terrain_width*terrain_depth,{});
        contact_floor_bins.assign(terrain_bins.size(),{});
        auto add=[&](std::vector<std::vector<int>> &bins,Rect2 r,int id) {
            Vector2 end=r.get_end();
            int first=terrain_bin(r.position),last=terrain_bin(end);
            for (int z=first/terrain_width;z<=last/terrain_width;++z)
                for (int x=first%terrain_width;x<=last%terrain_width;++x) bins[z*terrain_width+x].push_back(id);
        };
        for (size_t i=0;i<floors.size();++i) {
            add(terrain_bins,floors[i].grow(.00001f),int(i));
            add(contact_floor_bins,floors[i].grow(.111f),int(i));
        }
        for (size_t i=0;i<polygons.size();++i) add(terrain_bins,polygons[i].bounds,int(floors.size()+i));
        for (size_t i=0;i<ramps.size();++i) add(terrain_bins,ramps[i].bounds.grow(.00001f),int(floors.size()+polygons.size()+i));
    }
    bool is_void(Vector2 point) const {
        for (auto r:voids) if (r.has_point(point) && !std::isfinite(floor_height(point))) return true;
        return false;
    }
    const std::vector<int> &nearby_walls(Vector3 point) const {
        int x=int(std::floor((point.x-origin.x)/cell_size)),z=int(std::floor((point.z-origin.z)/cell_size));
        return x>=0 && z>=0 && x<nx && z<nz ? wall_bins[z*nx+x] : no_walls;
    }
    bool face_blocked(int component, int x, int y, int z) const {
        if (!in_grid(x, y, z)) return true;
        if (safe_goal && component==2 && valve_closed[index(x,y,z)]) return true;
        return is_solid(x, y, z) || is_solid(x - (component == 0), y - (component == 1), z - (component == 2));
    }
    bool valve_boundary(int cell, int offset) const {
        return safe_goal && ((offset==-nx && valve_closed[cell]) || (offset==nx && valve_closed[cell+nx]));
    }
    Vector3 face_offset(int component) const {
        return component == 0 ? Vector3(0, .5f, .5f) :
               (component == 1 ? Vector3(.5f, 0, .5f) : Vector3(.5f, .5f, 0));
    }
    void touch(FaceGrid &field, int i) {
        if (!field.valid[i]) { field.valid[i] = 1; field.touched.push_back(i); }
    }
    void clear_grid() {
        for (int i : liquid_cells) { liquid_id[i] = -1; marker_count[i] = 0; }
        liquid_cells.clear();
        for (auto &field : faces) {
            for (int i : field.touched) {
                field.velocity[i] = field.before[i] = field.weight[i] = 0;
                field.valid[i] = 0;
            }
            field.touched.clear();
        }
    }
    void scatter(int particle) {
        Vector3 point=mac_transfer_point(positions[particle]),velocity=velocities[particle];
        Vector3 grid_point = (point - origin) / cell_size;
        int cx = int(std::floor(grid_point.x)), cy = int(std::floor(grid_point.y)), cz = int(std::floor(grid_point.z));
        if (in_grid(cx, cy, cz)) {
            int cell = index(cx, cy, cz);
            if (!solid[cell]) ++marker_count[cell];
            if (!solid[cell] && liquid_id[cell] == -1) {
                liquid_id[cell] = int(liquid_cells.size()); liquid_cells.push_back(cell);
            }
        }
        for (int component = 0; component < 3; ++component) {
            Vector3 q = grid_point - face_offset(component);
            int bx = int(std::floor(q.x)), by = int(std::floor(q.y)), bz = int(std::floor(q.z));
            Vector3 f(q.x - bx, q.y - by, q.z - bz);
            FaceGrid &field = faces[component];
            for (int dy = 0; dy <= 1; ++dy) for (int dz = 0; dz <= 1; ++dz) for (int dx = 0; dx <= 1; ++dx) {
                int x = bx + dx, y = by + dy, z = bz + dz;
                if (face_blocked(component, x, y, z)) continue;
                float weight = (dx ? f.x : 1 - f.x) * (dy ? f.y : 1 - f.y) * (dz ? f.z : 1 - f.z);
                if (weight <= 0) continue;
                int i = index(x, y, z); touch(field, i);
                float value=velocity[component];

                field.weight[i] += weight; field.velocity[i] += weight * value;
            }
        }
    }
    void extrapolate(int component, int layers) {
        FaceGrid &field = faces[component];
        std::vector<int> frontier = field.touched, next;
        for (int layer = 0; layer < layers; ++layer) {
            next.clear();
            for (int current : frontier) {
                int y = current / plane, z = (current % plane) / nx, x = current % nx;
                for (int axis = 0; axis < 3; ++axis) for (int sign : {-1, 1}) {
                    int xx = x + (axis == 0 ? sign : 0), yy = y + (axis == 1 ? sign : 0), zz = z + (axis == 2 ? sign : 0);
                    if (face_blocked(component, xx, yy, zz)) continue;
                    int target = index(xx, yy, zz);
                    if (field.valid[target]) continue;
                    field.valid[target] = 2; next.push_back(target);
                }
            }
            for (int target : next) {
                int y = target / plane, z = (target % plane) / nx, x = target % nx;
                float sum = 0; int samples = 0;
                for (int axis = 0; axis < 3; ++axis) for (int sign : {-1, 1}) {
                    int xx = x + (axis == 0 ? sign : 0), yy = y + (axis == 1 ? sign : 0), zz = z + (axis == 2 ? sign : 0);
                    if (!in_grid(xx, yy, zz)) continue;
                    int neighbor = index(xx, yy, zz);
                    if (field.valid[neighbor] == 1) { sum += field.velocity[neighbor]; ++samples; }
                }
                field.velocity[target] = samples ? sum / samples : 0;
            }
            for (int target : next) { field.valid[target] = 1; field.touched.push_back(target); }
            frontier = next;
        }
    }
    float sample_component(int component, Vector3 point, bool old) const {
        Vector3 q = (point - origin) / cell_size - face_offset(component);
        int bx = int(std::floor(q.x)), by = int(std::floor(q.y)), bz = int(std::floor(q.z));
        Vector3 f(q.x - bx, q.y - by, q.z - bz);
        const FaceGrid &field = faces[component]; float value = 0;
        for (int dy = 0; dy <= 1; ++dy) for (int dz = 0; dz <= 1; ++dz) for (int dx = 0; dx <= 1; ++dx) {
            int x = bx + dx, y = by + dy, z = bz + dz;
            if (!in_grid(x, y, z)) continue;
            int i = index(x, y, z);
            float weight = (dx ? f.x : 1 - f.x) * (dy ? f.y : 1 - f.y) * (dz ? f.z : 1 - f.z);
            value += weight * (old ? field.before[i] : field.velocity[i]);
        }
        return value;
    }
    Vector3 sample_velocity(Vector3 point, bool old = false) const {
        point=mac_transfer_point(point);
        return sample_grid_velocity(point,old);
    }
    Vector3 sample_grid_velocity(Vector3 point, bool old = false) const {
        return Vector3(sample_component(0, point, old), sample_component(1, point, old), sample_component(2, point, old));
    }
    float divergence(int i) const {
        return (faces[0].velocity[i + 1] - faces[0].velocity[i] +
                faces[1].velocity[i + plane] - faces[1].velocity[i] +
                faces[2].velocity[i + nx] - faces[2].velocity[i]) / cell_size;
    }
    void apply_matrix(const std::vector<float> &input, std::vector<float> &output) const {
        const int neighbors[6] = {-1, 1, -nx, nx, -plane, plane};
        for (size_t k = 0; k < liquid_cells.size(); ++k) {
            int cell = liquid_cells[k]; float value = diagonal[k] * input[k];
            for (int offset : neighbors) {
                int id = liquid_id[cell + offset];
                if (id >= 0 && !valve_boundary(cell,offset)) value -= input[id];
            }
            output[k] = value;
        }
    }
    void project_pressure(float dt) {
        size_t size = liquid_cells.size();
        pressure.assign(size, 0); rhs.resize(size); residual.resize(size); direction.resize(size);
        preconditioned.resize(size); product.resize(size); diagonal.resize(size);
        const int neighbors[6] = {-1, 1, -nx, nx, -plane, plane};
        double rz = 0, b_squared = 0;
        for (size_t k = 0; k < size; ++k) {
            int cell = liquid_cells[k], d = 0;
            for (int offset : neighbors) if (!solid[cell + offset] && !valve_boundary(cell,offset)) ++d;
            diagonal[k] = std::max(d, 1);
            rhs[k] = -divergence(cell) * cell_size * cell_size * mass_density / dt;
            residual[k] = rhs[k]; preconditioned[k] = rhs[k] / diagonal[k]; direction[k] = preconditioned[k];
            rz += double(residual[k]) * preconditioned[k]; b_squared += double(rhs[k]) * rhs[k];
        }
        pressure_steps = 0;
        double tolerance = std::max(b_squared * 1e-8, 1e-10);
        for (int iteration = 0; iteration < 80 && rz > 1e-20; ++iteration) {
            apply_matrix(direction, product); double denominator = 0;
            for (size_t k = 0; k < size; ++k) denominator += double(direction[k]) * product[k];
            if (denominator <= 1e-20) break;
            float alpha = float(rz / denominator); double squared = 0;
            for (size_t k = 0; k < size; ++k) {
                pressure[k] += alpha * direction[k]; residual[k] -= alpha * product[k];
                squared += double(residual[k]) * residual[k];
            }
            pressure_steps = iteration + 1;
            if (squared < tolerance) break;
            double next_rz = 0;
            for (size_t k = 0; k < size; ++k) {
                preconditioned[k] = residual[k] / diagonal[k];
                next_rz += double(residual[k]) * preconditioned[k];
            }
            float beta = float(next_rz / rz);
            for (size_t k = 0; k < size; ++k) direction[k] = preconditioned[k] + beta * direction[k];
            rz = next_rz;
        }
        for (int component = 0; component < 3; ++component) {
            FaceGrid &field = faces[component]; int offset = component == 0 ? 1 : (component == 1 ? plane : nx);
            for (int i : field.touched) {
                int left = i - offset;
                if (left < 0 || solid[i] || solid[left] || (safe_goal && component==2 && valve_closed[i])) { field.velocity[i] = 0; continue; }
                int a = liquid_id[left], b = liquid_id[i];
                if (a < 0 && b < 0) continue;
                float pa = a >= 0 ? pressure[a] : 0, pb = b >= 0 ? pressure[b] : 0;
                field.velocity[i] -= dt * (pb - pa) / (mass_density * cell_size);
            }
        }
        maximum_divergence = 0;
        for (int cell : liquid_cells) maximum_divergence = std::max(maximum_divergence, std::abs(divergence(cell)));
    }
    Vector3 collide_box(Vector3 point, Vector3 lower, Vector3 upper, float r) const {
        Vector3 nearest(clampf(point.x, lower.x, upper.x), clampf(point.y, lower.y, upper.y), clampf(point.z, lower.z, upper.z));
        Vector3 difference = point - nearest; float distance = difference.length();
        if (distance >= r) return point;
        if (distance > 1e-7f) return point + difference * (r / distance - 1);
        Vector3 exits[6] = {Vector3(0, upper.y + r - point.y, 0), Vector3(lower.x - r - point.x, 0, 0), Vector3(upper.x + r - point.x, 0, 0), Vector3(0, 0, lower.z - r - point.z), Vector3(0, 0, upper.z + r - point.z), Vector3(0, lower.y - r - point.y, 0)};
        Vector3 best = exits[0];
        for (auto exit : exits) if (exit.length_squared() < best.length_squared()) best = exit;
        return point + best;
    }
    Vector3 constrain(Vector3 point, Vector3 previous) const {
        // Sweep the exposed faces before resolving rounded contacts. A
        // single nearest-face projection on adjacent solid tiles can push a
        // parcel through their hidden shared seam at an inside corner.
        const auto &candidates = curved ? nearby_walls(previous) : wall_indices;
        for (int i : candidates) {
            const auto &wall = walls[i]; Vector3 normal = wall_normals[i];
            Vector3 anchor(wall[0],0,wall[1]);
            float before = (previous-anchor).dot(normal), after = (point-anchor).dot(normal);
            if (before < radius - .0001f || after >= radius || before <= after) continue;
            float t = clampf((before-radius)/(before-after),0,1);
            Vector3 hit = previous.lerp(point,t);
            if (hit.y <= wall[4] || hit.y >= wall[5]) continue;
            Vector2 edge(wall[2]-wall[0],wall[3]-wall[1]);
            float along=Vector2(hit.x-wall[0],hit.z-wall[1]).dot(edge)/std::max(edge.length_squared(),1e-12f);
            bool on_face = curved ? along>=-.0001f && along<=1.0001f : (normal.x != 0 ? hit.z >= wall[1]-.0001f && hit.z <= wall[3]+.0001f : hit.x >= wall[0]-.0001f && hit.x <= wall[2]+.0001f);
            if (on_face) point += normal * (radius-after);
        }
        if (curved) for (int i:candidates) {
            const auto &wall=walls[i];
            for (int endpoint:{0,2}) {
                Vector2 centre(wall[endpoint],wall[endpoint+1]);
                Vector2 start(previous.x,previous.z),motion(point.x-previous.x,point.z-previous.z),offset=start-centre;
                float a=motion.length_squared(),b=2*offset.dot(motion),c=offset.length_squared()-radius*radius;
                float discriminant=b*b-4*a*c;
                if (a<1e-12f || c<-.000001f || discriminant<0) continue;
                float t=(-b-std::sqrt(discriminant))/(2*a);
                if (t<0 || t>1) continue;
                float y=previous.y+(point.y-previous.y)*t;
                if (y<=wall[4] || y>=wall[5]) continue;
                Vector2 at=start+motion*t,n=(at-centre).normalized(),rest=motion*(1-t);
                float inward=rest.dot(n);
                if (inward>=0) continue;
                Vector2 corrected=at+rest-n*inward;
                point.x=corrected.x; point.z=corrected.y;
            }
        }
        Vector2 xz(point.x, point.z);
        float floor = floor_height(xz);
        if (std::isfinite(floor) && point.y < floor + radius && previous.y >= floor + radius - .0001f) point.y = floor + radius;
        Vector3 q = (point - origin) / cell_size;
        int x = int(std::floor(q.x)), y = int(std::floor(q.y)), z = int(std::floor(q.z));
        bool needs_walls = in_grid(x, y, z) && vertical_wall[index(x, y, z)];
        if (curved) for (int pass=0;pass<3;++pass) for (int i:candidates) {
            const auto &wall=walls[i];
            if (point.y<wall[4]-radius || point.y>wall[5]+radius) continue;
            Vector2 a(wall[0],wall[1]),edge(wall[2]-wall[0],wall[3]-wall[1]);
            float t=Vector2(point.x-a.x,point.z-a.y).dot(edge)/std::max(edge.length_squared(),1e-12f);
            Vector2 horizontal=a+edge*clampf(t,0,1);
            Vector3 nearest(horizontal.x,clampf(point.y,wall[4],wall[5]),horizontal.y);
            float signed_distance=(point-Vector3(a.x,0,a.y)).dot(wall_normals[i]);
            float previous_side=(previous-Vector3(a.x,0,a.y)).dot(wall_normals[i]);
            // A face belongs to the fluid side from which it was approached.
            // Resolving the far face of a thin solid used to push water all
            // the way through low glass banks and invent a lateral impulse.
            if (t>=0 && t<=1 && point.y>wall[4] && point.y<wall[5] && previous_side>=-.002f && signed_distance<radius && signed_distance>-.15f) {
                point+=wall_normals[i]*(radius-signed_distance);
            } else {
                Vector3 difference=point-nearest; float distance=difference.length();
                if (distance>1e-7f && distance<radius) point+=difference*(radius/distance-1);
            }
        }
        if (!curved && needs_walls) for (int pass = 0; pass < 2; ++pass) for (const auto &tile : tiles) {
            const Rect2 &r = tile.rectangle;
            if (point.y >= tile.height + radius || point.y < base - radius || !r.grow(radius).has_point(Vector2(point.x, point.z))) continue;
            point = collide_box(point, Vector3(r.position.x, base, r.position.y), Vector3(r.get_end().x, tile.height, r.get_end().y), radius);
        }
        for (const auto &source:sources) {
            const Rect2 &r=source.bounds; float port=source.floor+.35f,roof=top+.07f;
            if (r.grow(radius).has_point(Vector2(point.x,point.z)) && std::abs(point.y-roof)<.15f)
                point=collide_box(point,Vector3(r.position.x,roof,r.position.y),Vector3(r.get_end().x,roof+.04f,r.get_end().y),radius);
            if (r.grow(radius).has_point(Vector2(point.x,point.z)) && std::abs(point.z-r.get_end().y)<.08f) {
                if (source.lower<port) point=collide_box(point,Vector3(r.position.x,source.lower,r.get_end().y-.025f),Vector3(r.get_end().x,port,r.get_end().y+.025f),radius);
                if (point.y>port-radius) point=collide_box(point,Vector3(r.position.x,port,r.get_end().y-.025f),Vector3(r.get_end().x,top+.11f,r.get_end().y+.025f),radius);
            }
        }
        for (const auto &box:obstacles) point=collide_box(point,box.position,box.get_end(),radius);
        point=constrain_ramps(point,radius);
        point=constrain_impact(point,radius);
        if (safe_goal && goal.grow(radius).has_point(Vector2(point.x,point.z)))
            point=collide_box(point,Vector3(goal.position.x,top+.01f,goal.position.y),Vector3(goal.get_end().x,top+.09f,goal.get_end().y),radius);
        // Rounded contacts at intersecting curved ledges can leave a point
        // inside the terrain after resolving a second face. Keep the last
        // valid contact state rather than let a parcel tunnel under the floor.
        float final_floor=floor_height(Vector2(point.x,point.z));
        if (curved && std::isfinite(final_floor) && point.y<final_floor+radius-.00001f && point.y>=base-radius) {
            float previous_floor=floor_height(Vector2(previous.x,previous.z));
            if (std::isfinite(previous_floor) && previous.y>=previous_floor+radius-.0001f) return previous;
        }
        return point;
    }
    void add_surface_tension(float dt) {
        for (int i : capillary_cells) { capillary_color[i] = 0; capillary_normal[i] = Vector3(); capillary_mark[i] = 0; }
        capillary_cells.clear();
        if (surface_tension <= 0) return;
        // Continuum surface force: sigma * curvature * grad(colour) / rho.
        // Smooth occupied cells before taking curvature; no spring links or
        // increased bulk viscosity are used to make water stick together.
        for (int cell : liquid_cells) {
            int y = cell / plane, z = (cell % plane) / nx, x = cell % nx;
            for (int dy = -2; dy <= 2; ++dy) for (int dz = -2; dz <= 2; ++dz) for (int dx = -2; dx <= 2; ++dx) {
                if (x+dx <= 1 || x+dx >= nx-2 || y+dy <= 1 || y+dy >= ny-2 || z+dz <= 1 || z+dz >= nz-2) continue;
                int i = index(x+dx,y+dy,z+dz);
                if (!solid[i] && !capillary_mark[i]) { capillary_mark[i] = 1; capillary_cells.push_back(i); }
            }
        }
        for (int i : capillary_cells) {
            float total_colour = 0, total_weight = 0;
            for (int dy=-1; dy<=1; ++dy) for (int dz=-1; dz<=1; ++dz) for (int dx=-1; dx<=1; ++dx) {
                int j = i + dx + dz*nx + dy*plane;
                float w = float((dx ? 1 : 2) * (dy ? 1 : 2) * (dz ? 1 : 2));
                // Reflect at a solid instead of attracting water into it.
                total_colour += w * (liquid_id[solid[j] ? i : j] >= 0 ? 1.f : 0.f); total_weight += w;
            }
            capillary_color[i] = total_colour / total_weight;
        }
        for (int i : capillary_cells) {
            auto colour = [&](int j) { return capillary_color[solid[j] ? i : j]; };
            Vector3 gradient(colour(i+1)-colour(i-1),colour(i+plane)-colour(i-plane),colour(i+nx)-colour(i-nx));
            if (gradient.length_squared() > 1e-7f) capillary_normal[i] = -gradient.normalized();
        }
        auto curvature = [&](int i) {
            if (!capillary_mark[i]) return 0.f;
            auto n = [&](int j) { return capillary_normal[solid[j] ? i : j]; };
            float k = (n(i+1).x-n(i-1).x+n(i+plane).y-n(i-plane).y+n(i+nx).z-n(i-nx).z)/(2*cell_size);
            return clampf(k,-2/cell_size,2/cell_size);
        };
        for (int component=0; component<3; ++component) {
            int offset = component==0 ? 1 : (component==1 ? plane : nx);
            for (int i : faces[component].touched) {
                int j=i-offset;
                if (j<0 || solid[i] || solid[j]) continue;
                float gradient=(capillary_color[i]-capillary_color[j])/cell_size;
                float k=.5f*(curvature(i)+curvature(j));
                faces[component].velocity[i] += dt * surface_tension / mass_density * k * gradient;
            }
        }
    }
    void add_subgrid_capillarity(float dt) {
        capillary_impulse.assign(count,Vector3());
        support_count.assign(count,0);
        if (!subgrid_capillarity || surface_tension<=0 || count<2) return;
        for (int i:particle_cells) particle_heads[i]=-1;
        particle_cells.clear(); capillary_pairs.clear();
        float h=cohesion_range*spacing,h2=h*h;
        for (int i=0;i<count;++i) if (active[i] && phases[i]==LIQUID) {
            Vector3 q=(positions[i]-origin)/cell_size;
            int x=int(std::floor(q.x)),y=int(std::floor(q.y)),z=int(std::floor(q.z));
            if (!in_grid(x,y,z)) continue;
            int cell=index(x,y,z);
            if (particle_heads[cell]<0) particle_cells.push_back(cell);
            particle_next[i]=particle_heads[cell]; particle_heads[cell]=i;
        }
        for (int i=0;i<count;++i) if (active[i] && phases[i]==LIQUID) {
            Vector3 p=positions[i],lo=(p-Vector3(h,h,h)-origin)/cell_size,hi=(p+Vector3(h,h,h)-origin)/cell_size;
            for (int y=std::max(0,int(std::floor(lo.y)));y<=std::min(ny-1,int(std::floor(hi.y)));++y)
            for (int z=std::max(0,int(std::floor(lo.z)));z<=std::min(nz-1,int(std::floor(hi.z)));++z)
            for (int x=std::max(0,int(std::floor(lo.x)));x<=std::min(nx-1,int(std::floor(hi.x)));++x)
            for (int j=particle_heads[index(x,y,z)];j>=0;j=particle_next[j]) {
                if (j<=i || captured[i]!=captured[j]) continue;
                Vector3 delta=positions[j]-p; float d2=delta.length_squared();
                if (d2<1e-10f || d2>=h2) continue;
                ++support_count[i]; ++support_count[j];
                capillary_pairs.push_back({i,j,delta,std::sqrt(d2)});
            }
        }
        // The grid resolves bulk surface tension. This symmetric correction
        // only supplies the missing support in thin, under-resolved films.
        // It has finite range, conserves pair momentum and leaves free spray
        // ballistic once it separates from the surface.
        float acceleration=2*cohesion_strength*surface_tension/(mass_density*radius*radius);

        for (const auto &pair:capillary_pairs) {
            int a=pair.a,b=pair.b;
            float sparse=clampf((32.f-float(std::min(support_count[a],support_count[b])))/24.f,0,1);
            if (sparse<=0) continue;
            Vector3 mid=(positions[a]+positions[b])*.5f;
            if (mid.y<floor_height(Vector2(mid.x,mid.z))+radius*.25f) continue;
            bool blocked=false;
            for (const auto &box:obstacles) if (box.has_point(mid)) { blocked=true; break; }
            if (blocked || impact_contains(mid) || ice_contains(mid)) continue;
            Vector3 n=pair.delta/pair.distance;
            float q=pair.distance/h,w=16*q*q*(1-q)*(1-q);
            float stretch=clampf((pair.distance-spacing)/spacing,-.25f,1.f);
            float impulse=acceleration*dt*stretch;
            impulse*=sparse*w/std::max(1.f,.5f*float(support_count[a]+support_count[b]));
            capillary_impulse[a]+=n*impulse; capillary_impulse[b]-=n*impulse;
        }
        float largest=0;
        for (int i=0;i<count;++i) largest=std::max(largest,capillary_impulse[i].length());
        float scale=largest>acceleration*dt ? acceleration*dt/largest : 1.f;
        for (auto &impulse:capillary_impulse) impulse*=scale;
    }
    void substep(float dt, Vector3 gravity) {
        clear_grid();
        update_impact(dt);
        advance_ice(dt,gravity);
        refresh_dynamic_solids();
        for (int i:valve_faces) valve_closed[i]=0;
        add_subgrid_capillarity(dt);
        for (int i = 0; i < count; ++i) if (active[i] && phases[i]==LIQUID) scatter(i);
        for (int component = 0; component < 3; ++component) {
            FaceGrid &field = faces[component];
            for (int i : field.touched) field.velocity[i] /= std::max(field.weight[i], 1e-12f);
            if (safe_goal && component==2) for (int i:valve_faces) {
                // A check valve admits a stream from the channel, but seals
                // against reverse flow and against draining into empty air.
                bool shut=marker_count[i]>0 && (marker_count[i-nx]==0 || field.velocity[i]+gravity.z*dt<0);
                valve_closed[i]=shut;
                if (shut) field.velocity[i]=0;
            }
            extrapolate(component, 2);
            for (int i : field.touched) field.before[i] = field.velocity[i];
            for (int i : field.touched) {
                if (safe_goal && component==2 && valve_closed[i]) field.velocity[i]=0;
                else field.velocity[i] += gravity[component] * dt;
            }
            if (viscosity > 0) {
                const int offsets[6] = {-1, 1, -nx, nx, -plane, plane};
                float amount = std::min(viscosity * dt / (cell_size * cell_size), .12f);
                for (int i : field.touched) {
                    float laplace = 0;
                    for (int offset : offsets) if (i + offset >= 0 && i + offset < total && field.valid[i + offset]) laplace += field.before[i + offset] - field.before[i];
                    field.velocity[i] += amount * laplace;
                }
            }
        }
        add_surface_tension(dt);
        project_pressure(dt);
        // Extend the projected field into air; retain the old field for FLIP.
        for (int component = 0; component < 3; ++component) {
            FaceGrid &field = faces[component];
            std::vector<int> keep;
            for (int i : field.touched) {
                int offset = component == 0 ? 1 : (component == 1 ? plane : nx);
                if (i >= offset && (liquid_id[i] >= 0 || liquid_id[i - offset] >= 0)) keep.push_back(i);
                else field.valid[i] = 0;
            }
            // Values outside fluid are updated by extrapolation, not gravity.
            auto all = field.touched; field.touched = keep; extrapolate(component, 2);
            for (int i : all) if (!field.valid[i]) { field.valid[i] = 1; field.touched.push_back(i); field.velocity[i] = 0; }
        }
        for (int i = 0; i < count; ++i) if (active[i] && phases[i]==LIQUID) {
            Vector3 previous=positions[i],transfer=mac_transfer_point(previous);
            Vector3 pic=sample_grid_velocity(transfer);
            Vector3 flip = velocities[i] + pic - sample_grid_velocity(transfer,true);
            // Bound unresolved velocity noise; coherent grid motion is kept.
            Vector3 residual_velocity=limited(flip-pic,velocity_noise_limit);
            Vector3 velocity=limited((pic+residual_velocity*flip_ratio)*std::exp(-drag*dt),max_speed);
            Vector3 midpoint = previous + pic * (.5f * dt);
            Vector3 candidate = previous + limited(sample_velocity(midpoint), max_speed) * dt;
            // Below grid resolution, detached spray travels ballistically.
            // Projecting one marker as a full liquid cell invents pressure and
            // gives a droplet spurious impulses at wall and floor contacts.
            Vector3 q = (transfer - origin) / cell_size;
            int x = int(std::floor(q.x)), y = int(std::floor(q.y)), z = int(std::floor(q.z));
            int nearby = 0;
            if (in_grid(x,y,z)) {
                int cell = index(x,y,z);
                for (int offset : {0,-1,1,-nx,nx,-plane,plane})
                    if (cell+offset>=0 && cell+offset<total) nearby+=marker_count[cell+offset];
            }
            if (nearby < 4) {
                velocity = limited((velocities[i] + gravity * dt) * std::exp(-drag * dt), max_speed);
                candidate = previous + (velocities[i] + velocity) * (.5f * dt);
            }
            // A film thinner than a MAC cell needs an analytic boundary
            // characteristic: voxel staircases must not pin it on a ramp.
            for (const auto &r:ramps) if (r.bounds.grow(.00001f).has_point(Vector2(previous.x,previous.z))) {
                float depth=previous.y-r.sample(Vector2(previous.x,previous.z));
                if (depth<cell_size*.85f && depth>-radius) {
                    Vector3 normal=Vector3(-r.gradient.x,1,-r.gradient.y).normalized();
                    Vector3 tangent=velocities[i]-normal*velocities[i].dot(normal);
                    Vector3 acceleration=gravity-normal*gravity.dot(normal);
                    velocity=limited((tangent+acceleration*dt)*std::exp(-drag*dt),max_speed);
                    candidate=previous+(tangent+velocity)*(.5f*dt);
                }
            }
            // Subcell surface forces must survive the MAC projection: putting
            // them only on the grid cancels attraction in thin free films.
            // Apply each symmetric impulse once, including to advection.
            velocity=limited(velocity+capillary_impulse[i],max_speed);
            candidate+=capillary_impulse[i]*(dt*.5f);
            Vector3 point = constrain(candidate, previous);
            admit_liquid(i,point);
            Vector3 contact=candidate-point;
            bool on_ramp=false;
            for (const auto &r:ramps) if (r.bounds.has_point(Vector2(point.x,point.z)) && point.y-r.sample(Vector2(point.x,point.z))<radius*2.5f) {
                Vector3 normal=Vector3(-r.gradient.x,1,-r.gradient.y).normalized();
                float inward=velocity.dot(normal); if (inward<0) velocity-=normal*inward;
                contact-=normal*contact.dot(normal); on_ramp=true;
            }
            if (!on_ramp && std::abs(contact.y)>1e-6f && contact.y*velocity.y>0) velocity.y=0;
            if (curved) {
                Vector2 normal(contact.x,contact.z),horizontal(velocity.x,velocity.z);
                if (normal.length_squared()>1e-10f) {
                    normal.normalize(); horizontal-=normal*std::max(horizontal.dot(normal),0.f);
                    velocity.x=horizontal.x; velocity.z=horizontal.y;
                }
            } else {
                if (std::abs(contact.x)>1e-6f && contact.x*velocity.x>0) velocity.x=0;
                if (std::abs(contact.z)>1e-6f && contact.z*velocity.z>0) velocity.z=0;
            }
            collide_ice(point,velocity);
            float floor_now=floor_height(Vector2(point.x,point.z)),floor_before=floor_height(Vector2(previous.x,previous.z));
            if (std::isfinite(floor_now) && std::abs(floor_now-floor_before)<.005f && point.y<floor_now+radius && point.y>floor_now-radius*2) {
                point.y=floor_now+radius; if (velocity.y<0) velocity.y=0;
            }
            positions[i] = point; velocities[i] = velocity;
            record_loss(i,previous,candidate);

        }
        preserve_thin_films(dt);
        regularize_liquid_particles();
        advance_vapor(dt,gravity);
        finish_ice_step();

    }

    void admit_liquid(int i,Vector3 &point) {
        // An independently closed compartment is a complete sealed vessel.
        // At the junction with a curved ribbon, resolving a box's closest
        // face alone can otherwise choose its outside face at the jamb.
        if (sources.size()>1 && initial_source[i]>=0) {
            const auto &source=sources[initial_source[i]];
            if (source.opening<.999f) {
                const auto &r=source.bounds;
                point.x=clampf(point.x,r.position.x+radius,r.get_end().x-radius);
                point.z=clampf(point.z,r.position.y+radius,r.get_end().y-.025f-radius);
                point.y=clampf(point.y,source.floor+radius,top+.07f-radius);
            }
        }
        if (collection_index>=0) {
            const auto &bank=sources[collection_index];
            Vector2 xz(point.x,point.z);
            if (bank.bounds.has_point(xz) && point.y>=floor_height(xz) && point.y<top) bank_captured[i]=1;
            if (bank.opening<.999f) {
                if (bank_captured[i]) {
                    point.x=clampf(point.x,bank.bounds.position.x+radius,bank.bounds.get_end().x-radius);
                    point.z=clampf(point.z,bank.bounds.position.y+radius,bank.bounds.get_end().y-radius);
                    point.y=clampf(point.y,floor_height(Vector2(point.x,point.z))+radius,top-radius);
                }
            } else if (bank_captured[i] && positions[i].z>=bank.bounds.position.y+radius-.0001f &&
                       point.z<bank.bounds.position.y+radius && point.x>=bank.bounds.position.x-radius &&
                       point.x<=bank.bounds.get_end().x+radius && point.y<top+.07f) {
                // Opening the outlet does not remove the inlet check valve.
                // Grid pressure alone cannot stop a FLIP residual from
                // carrying admitted water back into an earlier chamber.
                point.z=bank.bounds.position.y+radius;
            }
        }
        Vector2 goal_xz(point.x,point.z);
        if (safe_goal && goal_phase==LIQUID && !captured[i] && goal.has_point(goal_xz) && point.y>=floor_height(goal_xz) && point.y<top) {
            captured[i]=1; ++secured;
        }
        if (safe_goal && captured[i]) {
            // The retained volume stays active, visible and pressure
            // coupled inside the covered receiver; it is never despawned.
            point.x=clampf(point.x,goal.position.x+radius,goal.get_end().x-radius);
            point.z=clampf(point.z,goal.position.y+radius,goal.get_end().y-radius);
            point.y=clampf(point.y,floor_height(Vector2(point.x,point.z))+radius,top-radius);
        }
    }

    void preserve_thin_films(float dt) {
        if (!subgrid_capillarity || surface_tension<=0 || capillary_pairs.empty()) return;
        std::fill(capillary_impulse.begin(),capillary_impulse.end(),Vector3());
        float relaxation=1-std::exp(-20.f*cohesion_strength*dt);
        for (const auto &pair:capillary_pairs) {
            int a=pair.a,b=pair.b;
            if (!active[a] || !active[b] || captured[a] || captured[b]) continue;
            float sparse=clampf((32.f-float(std::min(support_count[a],support_count[b])))/24.f,0,1);
            if (sparse<=0) continue;
            Vector3 delta=positions[b]-positions[a]; float distance=delta.length();
            if (distance<1e-7f || distance>cohesion_range*spacing) continue;
            Vector3 mid=(positions[a]+positions[b])*.5f;
            if (mid.y<floor_height(Vector2(mid.x,mid.z))+radius*.25f) continue;
            bool blocked=false;
            for (const auto &box:obstacles) if (box.has_point(mid)) { blocked=true; break; }
            if (blocked || impact_contains(mid) || ice_contains(mid)) continue;
            Vector3 n=delta/distance;
            float separating=std::max((velocities[b]-velocities[a]).dot(n),0.f);
            // Dissipate only separation of neighbouring surface parcels.
            // The pair reaction preserves momentum; coherent translation,
            // and incoming impact speed are unchanged. Rebuild this
            // finite-range interaction every substep, with no lasting bonds.
            float impulse=.5f*relaxation*sparse*separating/std::max(1.f,.5f*float(support_count[a]+support_count[b]));
            capillary_impulse[a]+=n*impulse; capillary_impulse[b]-=n*impulse;
        }
        for (int i=0;i<count;++i) if (active[i] && phases[i]==LIQUID && !captured[i]) {
            Vector3 change=capillary_impulse[i]*(dt*.5f);
            if (change.length_squared()<1e-16f) continue;
            Vector3 previous=positions[i],candidate=previous+change;
            Vector3 point=constrain(candidate,previous);
            admit_liquid(i,point);
            velocities[i]=limited(velocities[i]+(point-previous)*(2/dt),max_speed);
            positions[i]=point;
            // Subgrid corrections can also cross a low open rim. Record
            // that crossing now, rather than start the next sweep outside
            // the board and misclassify a legitimate spill as a leak.
            record_loss(i,previous,candidate);
        }
    }

 #include "particle_relaxation.inc"

    // Sparse weighted-centroid surface reconstruction. Reflected samples
    // complete support at solid contacts; the vertical grid follows each step.
    int SX=122,SZ=188,SY=112,SLICE=SX*SZ,TOTAL=SLICE*SY;
    static constexpr float SURFACE_CELL = .06f, SURFACE_Y = .035f, KERNEL = .11f, ISO = .5f;
    Vector3 surface_origin = Vector3(-3.6f, -1.4f, -5.6f);
    std::vector<float> surface_field, surface_floor;
    std::vector<Vector3> surface_gradient, surface_vertices, surface_normals;
    std::vector<uint8_t> surface_flags;
    std::vector<int> surface_touched, surface_cells;
    Vector3 optical_right=Vector3(1,0,0), optical_up=Vector3(0,.85f,-.53f);
    Vector2 optical_origin; int optical_width=0,optical_height=0;
    static constexpr float OPTICAL_CELL=.035f,OPTICAL_KERNEL=.075f;
    struct OpticalCell { float depth=0,vx=0,vz=0; };
    std::vector<OpticalCell> optical_field;
    double optical_volume=0;
    void set_render_axes(Vector3 right,Vector3 up) {
        if (right.length_squared()<.5f || up.length_squared()<.5f) return;
        optical_right=right.normalized(); optical_up=(up-optical_right*up.dot(optical_right)).normalized();
    }
    void build_optical_field() {
        Vector2 low(1e9f,1e9f),high(-1e9f,-1e9f);
        int visible=0;
        for (int i=0;i<count;++i) if (active[i] && phases[i]==LIQUID) {
            Vector2 p(positions[i].dot(optical_right),positions[i].dot(optical_up)); low=low.min(p); high=high.max(p); ++visible;
        }
        optical_volume=0; optical_width=optical_height=0;
        if (!visible) { optical_field.clear(); return; }
        optical_origin=Vector2(std::floor((low.x-OPTICAL_KERNEL)/OPTICAL_CELL)*OPTICAL_CELL,std::floor((low.y-OPTICAL_KERNEL)/OPTICAL_CELL)*OPTICAL_CELL);
        optical_width=int(std::ceil((high.x+OPTICAL_KERNEL-optical_origin.x)/OPTICAL_CELL))+2;
        optical_height=int(std::ceil((high.y+OPTICAL_KERNEL-optical_origin.y)/OPTICAL_CELL))+2;
        optical_field.assign(optical_width*optical_height,OpticalCell());
        const float parcel=spacing*spacing*spacing,area=OPTICAL_CELL*OPTICAL_CELL,r2=OPTICAL_KERNEL*OPTICAL_KERNEL;
        for (int i=0;i<count;++i) if (active[i] && phases[i]==LIQUID) {
            Vector2 p(positions[i].dot(optical_right),positions[i].dot(optical_up));
            Vector2 q=(p-optical_origin)/OPTICAL_CELL;
            int cx=int(std::floor(q.x)),cy=int(std::floor(q.y)); float sum=0;
            for (int y=cy-2;y<=cy+3;++y) for (int x=cx-2;x<=cx+3;++x) {
                if (x<0 || y<0 || x>=optical_width || y>=optical_height) continue;
                Vector2 d=optical_origin+Vector2(x,y)*OPTICAL_CELL-p;
                float w=std::max(0.f,1-d.length_squared()/r2); sum+=w*w*w;
            }
            if (sum<=0) continue;
            float scale=parcel/(area*sum);
            for (int y=cy-2;y<=cy+3;++y) for (int x=cx-2;x<=cx+3;++x) {
                if (x<0 || y<0 || x>=optical_width || y>=optical_height) continue;
                Vector2 d=optical_origin+Vector2(x,y)*OPTICAL_CELL-p;
                float w=std::max(0.f,1-d.length_squared()/r2); w=w*w*w*scale;
                auto &cell=optical_field[y*optical_width+x];
                cell.depth+=w; cell.vx+=velocities[i].x*w; cell.vz+=velocities[i].z*w;
            }
        }
        for (const auto &cell:optical_field) optical_volume+=cell.depth*area;
    }
    Color optical_sample(Vector3 p) const {
        if (optical_width<2 || optical_height<2) return Color(0,.5f,.5f,1);
        Vector2 q=(Vector2(p.dot(optical_right),p.dot(optical_up))-optical_origin)/OPTICAL_CELL;
        int x=int(std::floor(q.x)),y=int(std::floor(q.y));
        if (x<0 || y<0 || x>=optical_width-1 || y>=optical_height-1) return Color(0,.5f,.5f,1);
        float dx=q.x-x,dy=q.y-y; OpticalCell sample;
        for (int j=0;j<2;++j) for (int k=0;k<2;++k) {
            float w=(j ? dy:1-dy)*(k ? dx:1-dx); const auto &c=optical_field[(y+j)*optical_width+x+k];
            sample.depth+=w*c.depth; sample.vx+=w*c.vx; sample.vz+=w*c.vz;
        }
        float inverse=sample.depth>1e-8f ? 1/sample.depth:0;
        return Color(clampf(sample.depth,0,2),.5f+.5f*clampf(sample.vx*inverse/max_speed,-1,1),.5f+.5f*clampf(sample.vz*inverse/max_speed,-1,1),1);
    }
    void splat_surface(Vector3 p, float weight, bool confined=false) {
        Vector3 c = (p - surface_origin) / Vector3(SURFACE_CELL,SURFACE_Y,SURFACE_CELL); float r2 = KERNEL * KERNEL;
        const int offsets[8] = {0, -1, -SX, -SX - 1, -SLICE, -SLICE - 1, -SLICE - SX, -SLICE - SX - 1};
        for (int y = std::max(1, int(std::floor(c.y)) - 4); y < std::min(SY - 1, int(std::ceil(c.y)) + 5); ++y) {
            float wy = surface_origin.y + y * SURFACE_Y, dy = wy - p.y;
            if (confined && wy>top) continue;
            if (dy * dy >= r2) continue;
            for (int z = std::max(1, int(std::floor(c.z)) - 2); z < std::min(SZ - 1, int(std::ceil(c.z)) + 3); ++z) {
                float dz = surface_origin.z + z * SURFACE_CELL - p.z, yz2 = dy * dy + dz * dz;
                if (yz2 >= r2) continue;
                for (int x = std::max(1, int(std::floor(c.x)) - 2); x < std::min(SX - 1, int(std::ceil(c.x)) + 3); ++x) {
                    if (confined && !goal.has_point(Vector2(surface_origin.x+x*SURFACE_CELL,surface_origin.z+z*SURFACE_CELL))) continue;
                    bool obstructed=false;
                    for (const auto &box:obstacles) if (box.has_point(Vector3(surface_origin.x+x*SURFACE_CELL,wy,surface_origin.z+z*SURFACE_CELL))) { obstructed=true; break; }
                    Vector3 sample(surface_origin.x+x*SURFACE_CELL,wy,surface_origin.z+z*SURFACE_CELL);
                    if (obstructed || impact_contains(sample) || (surface_selected_phase==LIQUID && ice_contains(sample))) continue;
                    int plane_index = z * SX + x;
                    if (wy < surface_floor[plane_index] - .0001f) continue;
                    float dx = surface_origin.x + x * SURFACE_CELL - p.x, q = 1 - (dx * dx + yz2) / r2;
                    if (q <= 0) continue;
                    int i = y * SLICE + plane_index;
                    if (surface_field[i] == 0) surface_touched.push_back(i);
                    surface_field[i] += weight * q * q * q;
                    surface_gradient[i] += p * (weight * q * q * q);
                    for (int offset : offsets) if (!surface_flags[i + offset]) { surface_flags[i + offset] = 1; surface_cells.push_back(i + offset); }
                }
            }
        }
    }
    Vector3 surface_contact(Vector3 point) const {
        for (const auto &box:obstacles) point=collide_box(point,box.position,box.get_end(),.001f);
        point=constrain_ramps(point,.001f);
        point=constrain_impact(point,.001f);
        if (surface_selected_phase==LIQUID) point=project_ice(point,.001f);
        float height = floor_height(Vector2(point.x, point.z));
        if (curved && point.y < base - .01f) return point;
        if (!std::isfinite(height) || point.y >= height + .001f) return point;
        if (height - point.y < SURFACE_Y) { point.y = height + .001f; return point; }
        if (point.y >= top) return point;
        Vector2 nearest(point.x, point.z); float best = KERNEL*KERNEL;
        // Marching tetrahedra can put a contact a fraction of a sample below
        // the floor. Include that floor instead of snapping to a distant wall.
        const auto &contacts=contact_floor_bins.empty() ? empty_terrain:contact_floor_bins[terrain_bin(Vector2(point.x,point.z))];
        for (int i:contacts) if (elevations[i] < point.y + SURFACE_Y + .001f) {
            Rect2 r = floors[i].grow(-.001f); auto end = r.get_end();
            Vector2 candidate(clampf(point.x, r.position.x, end.x), clampf(point.z, r.position.y, end.y));
            float distance = candidate.distance_squared_to(Vector2(point.x, point.z));
            if (distance < best) { nearest = candidate; best = distance; }
        }
        if (curved) {
            // Surface vertices lie within one reconstruction kernel of a
            // physical wall. Reuse its spatial bin instead of scanning every
            // curve edge for every triangle vertex on a phone.
            auto consider=[&](const std::vector<int> &indices) {
                for (int i:indices) {
                    const auto &wall=walls[i];
                    if (point.y<wall[4]-.002f || point.y>wall[5]+.002f) continue;
                    Vector2 a(wall[0],wall[1]),edge(wall[2]-wall[0],wall[3]-wall[1]);
                    float t=clampf((Vector2(point.x,point.z)-a).dot(edge)/std::max(edge.length_squared(),1e-12f),0,1);
                    Vector3 n=wall_normals[i];
                    Vector2 candidate=a+edge*t+Vector2(n.x,n.z)*.001f;
                    float distance=candidate.distance_squared_to(Vector2(point.x,point.z));
                    if (distance>=best) continue;
                    float h=floor_height(candidate);
                    if (std::isfinite(h) && h>point.y+.002f) continue;
                    nearest=candidate; best=distance;
                }
            };
            consider(nearby_walls(point));
        }
        point.x = nearest.x; point.z = nearest.y;
        float floor=floor_height(nearest);
        if (std::isfinite(floor) && floor-point.y<SURFACE_Y) point.y=std::max(point.y,floor+.001f);
        return point;
    }
    void smooth_free_surface() {
        if (surface_vertices.empty()) return;
        // Join the tetrahedra before smoothing: independent triangle normals
        // and octahedral parcel highlights exaggerate the reconstruction grid.
        std::unordered_map<int64_t,int> lookup;
        std::vector<Vector3> points,normals;
        lookup.reserve(surface_vertices.size()/3);
        points.reserve(surface_vertices.size()/3); normals.reserve(surface_vertices.size()/3);
        std::vector<int> vertex_ids; vertex_ids.reserve(surface_vertices.size());
        for (size_t i=0;i<surface_vertices.size();++i) {
            const auto &p=surface_vertices[i];
            int64_t x=int64_t(std::llround(p.x*100000)),y=int64_t(std::llround(p.y*100000)),z=int64_t(std::llround(p.z*100000));
            // Use a hash of signed coordinates, not a finite packed position.
            int64_t key=(x*73856093)^(y*19349663)^(z*83492791);
            auto found=lookup.find(key);
            int id;
            if (found==lookup.end()) { id=int(points.size()); lookup.emplace(key,id); points.push_back(p); normals.push_back(surface_normals[i]); }
            else {
                id=found->second;
                // Rare hash collisions must never weld unrelated surfaces.
                if (points[id].distance_squared_to(p)>1e-8f) { id=int(points.size()); points.push_back(p); normals.push_back(surface_normals[i]); }
            }
            vertex_ids.push_back(id);
        }
        // The topology is rebuilt at every visible update. Store adjacency
        // contiguously instead of allocating a growable vector per vertex.
        // Preserve all duplicates and insertion order, hence the same sums.
        std::vector<int> offsets(points.size()+1,0);
        for (int id:vertex_ids) offsets[id+1]+=2;
        for (size_t i=1;i<offsets.size();++i) offsets[i]+=offsets[i-1];
        auto cursor=offsets;
        std::vector<int> neighbours(offsets.back());
        for (size_t i=0;i<vertex_ids.size();i+=3) for (int k=0;k<3;++k) {
            int a=vertex_ids[i+k];
            neighbours[cursor[a]++]=vertex_ids[i+(k+1)%3]; neighbours[cursor[a]++]=vertex_ids[i+(k+2)%3];
        }
        std::vector<uint8_t> contact(points.size(),0);
        for (size_t i=0;i<points.size();++i) {
            float floor=floor_height(Vector2(points[i].x,points[i].z));
            contact[i]=std::isfinite(floor) && points[i].y-floor<.004f;
        }
        std::vector<Vector3> next(points.size());
        // Taubin's positive/negative pair removes sample-scale corrugation
        // without the steady shrinkage of a simple Laplacian blur. Actual
        // disconnected spray is appended afterwards and is never welded.
        for (int pass=0;pass<4;++pass) {
            float strength=(pass%2==0) ? .45f:-.47f;
            for (size_t i=0;i<points.size();++i) {
                if (contact[i] || offsets[i]==offsets[i+1]) { next[i]=points[i]; continue; }
                Vector3 mean;
                for (int j=offsets[i];j<offsets[i+1];++j) mean+=points[neighbours[j]];
                next[i]=points[i]+(mean/float(offsets[i+1]-offsets[i])-points[i])*strength;
            }
            points.swap(next);
        }
        for (auto &p:points) p=surface_contact(p);
        std::vector<Vector3> sums(points.size(),Vector3());
        for (size_t i=0;i<vertex_ids.size();i+=3) {
            int a=vertex_ids[i],b=vertex_ids[i+1],c=vertex_ids[i+2];
            Vector3 n=(points[b]-points[a]).cross(points[c]-points[a]);
            if (n.dot(normals[a]+normals[b]+normals[c])<0) n=-n;
            sums[a]+=n; sums[b]+=n; sums[c]+=n;
        }
        std::vector<Vector3> filtered(points.size());
        for (size_t i=0;i<points.size();++i) {
            Vector3 geometric=sums[i].length_squared()>1e-14f ? sums[i].normalized() : normals[i];
            filtered[i]=(normals[i]*.8f+geometric*.2f).normalized();
        }
        // A bilateral normal filter removes parcel-scale sparkle while
        // respecting opposite sides of thin sheets and true silhouette folds.
        for (int pass=0;pass<4;++pass) {
            for (size_t i=0;i<points.size();++i) {
                Vector3 sum=filtered[i]*2; float weight=2;
                for (int k=offsets[i];k<offsets[i+1];++k) {
                    int j=neighbours[k];
                    float w=std::max(0.f,filtered[i].dot(filtered[j])); w*=w;
                    sum+=filtered[j]*w; weight+=w;
                }
                next[i]=(sum/weight).normalized();
            }
            filtered.swap(next);
        }
        for (size_t i=0;i<vertex_ids.size();++i) {
            int id=vertex_ids[i]; surface_vertices[i]=points[id]; surface_normals[i]=filtered[id];
        }
    }
    Dictionary make_surface(int selected_phase=LIQUID) {
        surface_selected_phase=selected_phase;
        if (surface_field.empty()) {
            surface_field.assign(TOTAL, 0); surface_gradient.assign(TOTAL, Vector3()); surface_flags.assign(TOTAL, 0); surface_floor.resize(SLICE);
            for (int z = 0; z < SZ; ++z) for (int x = 0; x < SX; ++x) surface_floor[z * SX + x] = floor_height(Vector2(surface_origin.x + x * SURFACE_CELL, surface_origin.z + z * SURFACE_CELL));
        }
        for (int i : surface_touched) { surface_field[i] = 0; surface_gradient[i] = Vector3(); }
        for (int i : surface_cells) surface_flags[i] = 0;
        surface_touched.clear(); surface_cells.clear(); surface_vertices.clear(); surface_normals.clear();
        float volume = spacing * spacing * spacing;
        std::vector<uint8_t> isolated(count,0);
        if (selected_phase==LIQUID) {
            std::unordered_map<int64_t,std::vector<int>> bins;
            for (int i=0;i<count;++i) if (active[i] && phases[i]==LIQUID) {
                Vector3 p=positions[i]/KERNEL;
                bins[thermal_key(int(std::floor(p.x)),int(std::floor(p.y)),int(std::floor(p.z)))].push_back(i);
            }
            for (int i=0;i<count;++i) if (active[i] && phases[i]==LIQUID) {
                Vector3 p=positions[i]/KERNEL; int x=int(std::floor(p.x)),y=int(std::floor(p.y)),z=int(std::floor(p.z));
                bool alone=true;
                for (int dy=-1;dy<=1 && alone;++dy) for (int dz=-1;dz<=1 && alone;++dz) for (int dx=-1;dx<=1 && alone;++dx) {
                    auto found=bins.find(thermal_key(x+dx,y+dy,z+dz));
                    if (found==bins.end()) continue;
                    for (int j:found->second) if (j!=i && positions[j].distance_squared_to(positions[i])<KERNEL*KERNEL) { alone=false; break; }
                }
                isolated[i]=alone;
            }
        }
        float weight = 315 * volume / (64 * 3.14159265359f * KERNEL * KERNEL * KERNEL);
        for (int i = 0; i < count; ++i) if (active[i] && phases[i]==selected_phase && !isolated[i]) {
            auto p = positions[i];
            if (curved) {
                Vector3 normals[2],anchors[2]; float distances[2]={KERNEL,KERNEL}; int mirrors=0;
                for (int j:nearby_walls(p)) {
                    const auto &wall=walls[j];
                    if (p.y<wall[4]-.001f || p.y>wall[5]+.001f) continue;
                    Vector2 a(wall[0],wall[1]),edge(wall[2]-wall[0],wall[3]-wall[1]);
                    float t=clampf(Vector2(p.x-a.x,p.z-a.y).dot(edge)/std::max(edge.length_squared(),1e-12f),0,1);
                    Vector2 q=a+edge*t; float d=q.distance_to(Vector2(p.x,p.z));
                    if (d>=KERNEL) continue;
                    Vector3 n=wall_normals[j],anchor(a.x,0,a.y);
                    if ((p-anchor).dot(n)<-.001f) continue;
                    if (mirrors==0) { normals[0]=n; anchors[0]=anchor; distances[0]=d; mirrors=1; }
                    else if (std::abs(normals[0].dot(n))>.7f) {
                        if (d<distances[0]) { normals[0]=n; anchors[0]=anchor; distances[0]=d; }
                    } else if (d<distances[1]) { normals[1]=n; anchors[1]=anchor; distances[1]=d; mirrors=2; }
                }
                for (const auto &source:sources) if (mirrors<2 && (p.y>=source.lower || p.y>=source.floor+.35f) && source.bounds.has_point(Vector2(p.x,p.z)) && source.bounds.get_end().y-p.z<KERNEL) {
                    normals[mirrors]=Vector3(0,0,-1); anchors[mirrors]=Vector3(0,0,source.bounds.get_end().y); ++mirrors;
                }
                if (captured[i] && p.z-goal.position.y<KERNEL) {
                    bool reflected=false;
                    for (int m=0;m<mirrors;++m) if (normals[m].z>.9f) reflected=true;
                    if (!reflected && mirrors<2) { normals[mirrors]=Vector3(0,0,1); anchors[mirrors]=Vector3(0,0,goal.position.y); ++mirrors; }
                }
                float floor=floor_height(Vector2(p.x,p.z));
                for (int mask=0;mask<(1<<mirrors);++mask) {
                    Vector3 image=p;
                    for (int m=0;m<mirrors;++m) if (mask&(1<<m)) image-=normals[m]*(2*(image-anchors[m]).dot(normals[m]));
                    splat_surface(image,weight,captured[i]);
                    if (std::isfinite(floor) && p.y-floor<KERNEL) splat_surface(Vector3(image.x,2*floor-p.y,image.z),weight,captured[i]);
                }
                continue;
            }
            float mirror_x = 0, mirror_z = 0, distance_x = KERNEL, distance_z = KERNEL;
            for (const auto &wall : walls) {
                if (p.y < wall[4] - .001f || p.y > wall[5] + .001f) continue;
                if (std::abs(wall[0] - wall[2]) < .0001f && p.z >= wall[1] && p.z <= wall[3]) {
                    float d = std::abs(p.x - wall[0]);
                    if (d < distance_x) { distance_x = d; mirror_x = wall[0]; }
                } else if (std::abs(wall[1] - wall[3]) < .0001f && p.x >= wall[0] && p.x <= wall[2]) {
                    float d = std::abs(p.z - wall[1]);
                    if (d < distance_z) { distance_z = d; mirror_z = wall[1]; }
                }
            }
            if ((p.y >= gate_lower || p.y >= elevations[0] + .35f) && reservoir.has_point(Vector2(p.x,p.z)) && reservoir.get_end().y - p.z < distance_z) {
                distance_z = reservoir.get_end().y - p.z; mirror_z = reservoir.get_end().y;
            }
            float floor = floor_height(Vector2(p.x,p.z));
            int copies_x = distance_x < KERNEL ? 2 : 1, copies_z = distance_z < KERNEL ? 2 : 1;
            for (int ix = 0; ix < copies_x; ++ix) for (int iz = 0; iz < copies_z; ++iz) {
                Vector3 image(ix ? 2 * mirror_x - p.x : p.x, p.y, iz ? 2 * mirror_z - p.z : p.z);
                splat_surface(image, weight);
                if (std::isfinite(floor) && p.y - floor < KERNEL) splat_surface(Vector3(image.x, 2 * floor - p.y, image.z), weight);
            }
        }
        // Zhu-Bridson weighted-centroid reconstruction. A fixed colour
        // threshold erases a stretched, shallow sheet; a local distance to
        // neighbouring fluid markers keeps that sheet a coherent surface.
        for (int i : surface_touched) {
            Vector3 point=surface_origin+Vector3((i%SLICE)%SX*SURFACE_CELL,(i/SLICE)*SURFACE_Y,((i%SLICE)/SX)*SURFACE_CELL);
            Vector3 mean=surface_gradient[i]/std::max(surface_field[i],1e-12f);
            Vector3 offset=point-mean;
            float distance=offset.length();
            float floor=surface_floor[i%SLICE];
            if (selected_phase==LIQUID && std::isfinite(floor) && point.y-floor<.11f && mean.y-floor<.08f) {
                // A wet subcell film is wide and shallow, rather than a row
                // of spheres. Match the physical neighbour radius while
                // preserving the reconstruction ellipsoid's volume.
                Vector3 normal(0,1,0);
                for (const auto &r:ramps) if (r.bounds.has_point(Vector2(point.x,point.z))) normal=Vector3(-r.gradient.x,1,-r.gradient.y).normalized();
                float stretch=1+.25f*clampf((.08f-(mean.y-floor))/.04f,0,1);
                float perpendicular=offset.dot(normal);
                Vector3 tangent=offset-normal*perpendicular;
                float square=stretch*stretch;
                distance=std::sqrt(tangent.length_squared()/square+perpendicular*perpendicular*square*square);
            }
            surface_field[i]=clampf(.5f+(spacing*.90f-distance)/KERNEL,0,1);
        }
        for (int i : surface_touched) {
            surface_gradient[i]=Vector3((surface_field[i+1]-surface_field[i-1])/(2*SURFACE_CELL),(surface_field[i+SLICE]-surface_field[i-SLICE])/(2*SURFACE_Y),(surface_field[i+SX]-surface_field[i-SX])/(2*SURFACE_CELL));
        }
        if (selected_phase==LIQUID) for (int pass=0;pass<3;++pass) {
            std::vector<Vector3> smooth; smooth.reserve(surface_touched.size());
            for (int i:surface_touched) {
                Vector3 n=surface_gradient[i]*4;
                for (int o:{-1,1,-SX,SX,-SLICE,SLICE}) n+=surface_gradient[i+o];
                smooth.push_back(n*.1f);
            }
            for (size_t k=0;k<surface_touched.size();++k) surface_gradient[surface_touched[k]]=smooth[k];
        }
        const int corners[8] = {0, 1, SX + 1, SX, SLICE, SLICE + 1, SLICE + SX + 1, SLICE + SX};
        const int tets[6][4] = {{0,5,1,6},{0,1,2,6},{0,2,3,6},{0,3,7,6},{0,7,4,6},{0,4,5,6}};
        const int edges[6][2] = {{0,1},{1,2},{2,0},{0,3},{1,3},{2,3}};
        const int tris[16][7] = {{-1},{0,3,2,-1},{0,1,4,-1},{1,4,2,2,4,3,-1},{1,2,5,-1},{0,3,5,0,5,1,-1},{0,2,5,0,5,4,-1},{5,4,3,-1},{3,4,5,-1},{4,5,0,5,2,0,-1},{1,5,0,5,3,0,-1},{5,2,1,-1},{3,4,2,2,4,1,-1},{4,1,0,-1},{2,3,0,-1},{-1}};
        float values[8]; Vector3 points[8], normals[8], ep[6], en[6]; bool projected[6];
        for (int i : surface_cells) {
            int mask = 0;
            for (int k = 0; k < 8; ++k) { values[k] = surface_field[i + corners[k]]; if (values[k] >= ISO) mask |= 1 << k; }
            if (!mask || mask == 255) continue;
            for (int k = 0; k < 8; ++k) {
                int n = i + corners[k], slice = n % SLICE;
                points[k] = surface_origin + Vector3((slice % SX)*SURFACE_CELL,(n / SLICE)*SURFACE_Y,(slice / SX)*SURFACE_CELL);
                normals[k] = -surface_gradient[n];
            }
            for (const auto &tet : tets) {
                int m = 0; for (int k = 0; k < 4; ++k) if (values[tet[k]] >= ISO) m |= 1 << k;
                if (tris[m][0] < 0) continue;
                for (int e = 0; e < 6; ++e) {
                    int a = tet[edges[e][0]], b = tet[edges[e][1]];
                    if ((values[a] >= ISO) == (values[b] >= ISO)) continue;
                    float t = clampf((ISO - values[a]) / (values[b] - values[a]), 0, 1);
                    Vector3 raw=points[a].lerp(points[b],t);
                    ep[e] = surface_contact(raw);
                    projected[e]=(raw-ep[e]).length_squared()>1e-6f;
                    Vector3 n = normals[a].lerp(normals[b], t); en[e] = n.length_squared() > 1e-8f ? n.normalized() : Vector3(0,1,0);
                }
                for (int t = 0; tris[m][t] >= 0; t += 3) {
                    int a = tris[m][t], b = tris[m][t + 1], c = tris[m][t + 2];
                    if ((ep[b] - ep[a]).cross(ep[c] - ep[a]).dot(en[a] + en[b] + en[c]) > 0) std::swap(b,c);
                    if (projected[a] || projected[b] || projected[c]) {
                        Vector3 normal=(ep[b]-ep[a]).cross(ep[c]-ep[a]);
                        if (normal.length_squared()>1e-12f) {
                            normal.normalize();
                            if (normal.dot(en[a]+en[b]+en[c])<0) normal=-normal;
                            for (int e:{a,b,c}) en[e]=(en[e]*.35f+normal*.65f).normalized();
                        }
                    }
                    for (int e : {a,b,c}) { surface_vertices.push_back(ep[e]); surface_normals.push_back(en[e]); }
                }
            }
        }
        if (selected_phase==LIQUID) smooth_free_surface();
        // Sparse spray has too little kernel support for an isosurface.
        // Keep those real markers visible as small 3D droplets.
        const size_t drop_start=surface_vertices.size();
        std::vector<Color> drop_colors;
        // Exact volume of the unit subdivided octahedron below. A true
        // isolated parcel keeps the same shape as it crosses voxel samples.
        float drop_radius=std::cbrt(volume*(selected_phase==ICE ? 1000.f/917.f:1.f)/2.94280904158f);
        Vector3 view=optical_right.cross(optical_up).normalized();
        const Vector3 droplet_axes[6] = {Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,1,0),Vector3(0,-1,0),Vector3(0,0,1),Vector3(0,0,-1)};
        const int droplet_faces[8][3] = {{2,0,4},{2,4,1},{2,1,5},{2,5,0},{3,4,0},{3,1,4},{3,5,1},{3,0,5}};
        for (int i = 0; i < count; ++i) if (active[i] && phases[i]==selected_phase) {
            Vector3 q = (positions[i] - surface_origin) / Vector3(SURFACE_CELL,SURFACE_Y,SURFACE_CELL);
            int x = int(std::floor(q.x)), y = int(std::floor(q.y)), z = int(std::floor(q.z));
            if (x <= 0 || y <= 0 || z <= 0 || x >= SX-1 || y >= SY-1 || z >= SZ-1) continue;
            float support=0;
            for (int o:corners) support=std::max(support,surface_field[y*SLICE+z*SX+x+o]);
            if (!isolated[i] && support>=ISO) continue;
            for (const auto &triangle:droplet_faces) {
                Vector3 a=droplet_axes[triangle[0]],b=droplet_axes[triangle[1]],c=droplet_axes[triangle[2]];
                Vector3 ab=(a+b).normalized(),bc=(b+c).normalized(),ca=(c+a).normalized();
                const Vector3 vertices[12]={a,ab,ca,ab,b,bc,ca,bc,c,ab,bc,ca};
                for (Vector3 n:vertices) {
                    surface_vertices.push_back(positions[i]+n*drop_radius); surface_normals.push_back(n);
                    drop_colors.push_back(Color(2*drop_radius*std::abs(n.dot(view)),.5f+.5f*velocities[i].x/max_speed,.5f+.5f*velocities[i].z/max_speed,1));
                }
            }
        }
        PackedVector3Array vertices_out, normals_out;
        vertices_out.resize(surface_vertices.size()); normals_out.resize(surface_normals.size());
        if (!surface_vertices.empty()) {
            std::copy(surface_vertices.begin(), surface_vertices.end(), vertices_out.ptrw());
            std::copy(surface_normals.begin(), surface_normals.end(), normals_out.ptrw());
        }
        // Projected physical parcel volume estimates the optical path along
        // this camera's rays. Unlike height above terrain it also describes
        // falling sheets, piled water and an almost transparent wet film.
        if (selected_phase==LIQUID) build_optical_field();
        PackedColorArray colors_out; colors_out.resize(surface_vertices.size());
        Color *colors=colors_out.ptrw();
        for (size_t i=0;i<surface_vertices.size();++i)
            colors[i]=selected_phase==LIQUID ? (i<drop_start ? optical_sample(surface_vertices[i]) : drop_colors[i-drop_start]) : Color(0,0,0,1);
        Dictionary result; result["vertices"] = vertices_out; result["normals"] = normals_out; result["colors"] = colors_out; result["optical_volume"]=optical_volume; return result;
    }

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure", "configuration"), &NativeLiquidSolver::configure);
        ClassDB::bind_method(D_METHOD("reset"), &NativeLiquidSolver::reset);
        ClassDB::bind_method(D_METHOD("step", "delta", "tilt"), &NativeLiquidSolver::step);
        ClassDB::bind_method(D_METHOD("settle", "delta", "tilt"), &NativeLiquidSolver::settle);
        ClassDB::bind_method(D_METHOD("set_gate_opening", "amount"), &NativeLiquidSolver::set_gate_opening);
        ClassDB::bind_method(D_METHOD("set_source_opening", "id", "amount"), &NativeLiquidSolver::set_source_opening);
        ClassDB::bind_method(D_METHOD("set_render_axes", "right", "up"), &NativeLiquidSolver::set_render_axes);
        ClassDB::bind_method(D_METHOD("get_state"), &NativeLiquidSolver::get_state);
        ClassDB::bind_method(D_METHOD("build_surface"), &NativeLiquidSolver::build_surface);
        ClassDB::bind_method(D_METHOD("build_ice_surface"), &NativeLiquidSolver::build_ice_surface);
        ClassDB::bind_method(D_METHOD("set_particle_enthalpy", "index", "enthalpy"), &NativeLiquidSolver::set_particle_enthalpy);
        ClassDB::bind_method(D_METHOD("sample_floor", "point"), &NativeLiquidSolver::floor_height);
        ClassDB::bind_method(D_METHOD("set_particle_state", "index", "position", "velocity"), &NativeLiquidSolver::set_particle_state);
    }
public:
    void configure(const Dictionary &cfg) {
        terrain_bins.clear(); contact_floor_bins.clear();
        floors.clear(); elevations.clear(); tiles.clear(); walls.clear(); polygons.clear(); voids.clear(); openings.clear(); obstacles.clear(); ramps.clear();
        Array fs = cfg["regions"], ts = cfg["tiles"], ws = cfg["walls"];
        PackedFloat32Array heights = cfg["elevations"];
        for (int i = 0; i < fs.size(); ++i) { floors.push_back(Rect2(fs[i])); elevations.push_back(i < heights.size() ? heights[i] : 0); }
        for (int i = 0; i < ts.size(); ++i) { Dictionary t = ts[i]; tiles.push_back(Tile{Rect2(t["bounds"]), float(t["height"])}); }
        for (int i = 0; i < ws.size(); ++i) { PackedFloat32Array w = ws[i]; std::array<float,6> a{}; for (int j = 0; j < 6; ++j) a[j] = w[j]; walls.push_back(a); }
        curved=cfg.has("curved") && bool(cfg["curved"]);
        if (cfg.has("polygons")) {
            Array ps=cfg["polygons"]; PackedFloat32Array hs=cfg["polygon_heights"];
            for (int i=0;i<ps.size();++i) polygons.push_back(read_polygon(PackedVector2Array(ps[i]),hs[i]));
        }
        if (cfg.has("voids")) { Array vs=cfg["voids"]; for (int i=0;i<vs.size();++i) voids.push_back(Rect2(vs[i])); }
        if (cfg.has("openings")) { Array os=cfg["openings"]; for (int i=0;i<os.size();++i) openings.push_back(read_polygon(PackedVector2Array(os[i]))); }
        if (cfg.has("ramps")) {
            Array list=cfg["ramps"];
            for (int i=0;i<list.size();++i) {
                Dictionary r=list[i]; Rect2 rect=r["bounds"]; Vector2 axis=r["axis"];
                float length=std::abs(axis.x*rect.size.x)+std::abs(axis.y*rect.size.y);
                Vector2 start=rect.position+Vector2(axis.x<0 ? rect.size.x:0,axis.y<0 ? rect.size.y:0);
                ramps.push_back({rect,axis*((float(r["end_height"])-float(r["start_height"]))/length),start,float(r["start_height"])});
            }
        }
        configure_phases(cfg);
        bounds = cfg["bounds"]; reservoir = cfg.has("reservoir") ? Rect2(cfg["reservoir"]) : Rect2(cfg["spawn"]); goal = cfg["goal"];
        safe_goal=cfg.has("safe_goal") && bool(cfg["safe_goal"]);
        sources.clear(); collection_index=-1;
        Array authored=cfg.has("sources") ? Array(cfg["sources"]) : Array();
        if (authored.is_empty()) {
            SealedSource source; source.id=cfg.has("source_id") ? StringName(cfg["source_id"]) : StringName("source");
            source.bounds=reservoir; source.floor=elevations[0]; source.fill=1; sources.push_back(source);
        } else for (int i=0;i<authored.size();++i) {
            Dictionary data=authored[i]; SealedSource source; source.id=data["id"]; source.bounds=data["bounds"];
            source.floor=data["height"]; source.fill=data["fill"]; sources.push_back(source);
            if (cfg.has("collection_source") && source.id==StringName(cfg["collection_source"])) collection_index=i;
        }
        if (cfg.has("obstacles")) { Array boxes=cfg["obstacles"]; for (int i=0;i<boxes.size();++i) obstacles.push_back(AABB(boxes[i])); }
        count = int(cfg["count"]); top = float(cfg["top"]); base = float(cfg["base"]); spacing = float(cfg["spacing"]); radius = float(cfg["radius"]);
        build_terrain_index();
        lowest_floor=top;
        for (auto height:elevations) lowest_floor=std::min(lowest_floor,height);
        for (const auto &p:polygons) lowest_floor=std::min(lowest_floor,p.height);
        for (const auto &r:ramps) lowest_floor=std::min(lowest_floor,std::min(r.sample(r.bounds.position),r.sample(r.bounds.get_end())));
        wall_normals.clear(); wall_indices.clear();
        for (const auto &wall : walls) {
            Vector2 midpoint((wall[0]+wall[2])*.5f,(wall[1]+wall[3])*.5f);
            bool x_face = std::abs(wall[0]-wall[2]) < .0001f;
            Vector2 axis = curved ? Vector2(-(wall[3]-wall[1]),wall[2]-wall[0]).normalized() : (x_face ? Vector2(1,0) : Vector2(0,1));
            float sign = floor_height(midpoint+axis*.001f) < floor_height(midpoint-axis*.001f) ? 1.f : -1.f;
            wall_normals.push_back(Vector3(axis.x*sign,0,axis.y*sign));
            wall_indices.push_back(int(wall_indices.size()));
        }
        mass_density = float(cfg["rho"]); max_speed = float(cfg["max_speed"]); drag = float(cfg["drag"]); viscosity = float(cfg["viscosity"]);
        surface_tension = cfg.has("surface_tension") ? float(cfg["surface_tension"]) : .072f;
        velocity_noise_limit=cfg.has("velocity_noise_limit") ? clampf(float(cfg["velocity_noise_limit"]),0,.4f) : .40f;
        subgrid_capillarity=!cfg.has("subgrid_capillarity") || bool(cfg["subgrid_capillarity"]);
        cohesion_strength=cfg.has("cohesion_strength") ? clampf(float(cfg["cohesion_strength"]),0,4) : 3.f;
        cohesion_range=cfg.has("cohesion_range") ? clampf(float(cfg["cohesion_range"]),2,3.2f) : 2.8f;
        required = float(cfg["required"]); hold_seconds = float(cfg["hold"]);
        flow_speed = cfg.has("flow_speed") ? clampf(float(cfg["flow_speed"]), .5f, 1.5f) : 1.15f;
        ERR_FAIL_COND(count < 1 || count > 32768 || spacing <= 0 || floors.empty());
        origin = Vector3(std::floor((bounds.position.x - .49f) / cell_size) * cell_size, std::floor((base - (curved ? 1.f : .7f)) / cell_size) * cell_size, std::floor((bounds.position.y - .49f) / cell_size) * cell_size);
        nx = int(std::ceil((bounds.get_end().x + .49f - origin.x) / cell_size)) + 2;
        nz = int(std::ceil((bounds.get_end().y + .49f - origin.z) / cell_size)) + 2;
        ny = int(std::ceil((top + 1.2f - origin.y) / cell_size)) + 2;
        plane = nx * nz; total = plane * ny;
        particle_heads.assign(total,-1); particle_next.resize(count); particle_cells.clear();
        wall_bins.clear();
        if (curved) {
            wall_bins.resize(plane);
            for (size_t i=0;i<walls.size();++i) {
                const auto &w=walls[i];
                int x0=std::max(0,int(std::floor((std::min(w[0],w[2])-.15f-origin.x)/cell_size)));
                int x1=std::min(nx-1,int(std::floor((std::max(w[0],w[2])+.15f-origin.x)/cell_size)));
                int z0=std::max(0,int(std::floor((std::min(w[1],w[3])-.15f-origin.z)/cell_size)));
                int z1=std::min(nz-1,int(std::floor((std::max(w[1],w[3])+.15f-origin.z)/cell_size)));
                for (int z=z0;z<=z1;++z) for (int x=x0;x<=x1;++x) wall_bins[z*nx+x].push_back(int(i));
            }
        }
        solid.assign(total, 1); vertical_wall.assign(total, 1); liquid_id.assign(total, -1); marker_count.assign(total, 0); liquid_cells.clear();
        capillary_color.assign(total,0); capillary_normal.assign(total,Vector3()); capillary_mark.assign(total,0); capillary_cells.clear();
        std::vector<float> floor_cache(plane);
        for (int z=0;z<nz;++z) for (int x=0;x<nx;++x) floor_cache[z*nx+x]=floor_height(Vector2(origin.x+(x+.5f)*cell_size,origin.z+(z+.5f)*cell_size));
        for (int y = 1; y < ny - 1; ++y) for (int z = 1; z < nz - 1; ++z) for (int x = 1; x < nx - 1; ++x) {
            Vector3 p = origin + Vector3(x + .5f, y + .5f, z + .5f) * cell_size;
            bool roof=false,header=false;
            for (const auto &source:sources) {
                const auto &r=source.bounds;
                roof|=r.has_point(Vector2(p.x,p.z)) && p.y>=top+.07f && p.y<top+.11f;
                header|=p.x>=r.position.x && p.x<=r.get_end().x && std::abs(p.z-r.get_end().y)<.035f && p.y>source.floor+.35f && p.y<top+.11f;
            }
            bool obstruction=false;
            for (const auto &box:obstacles) if (box.has_point(p)) { obstruction=true; break; }
            bool goal_roof=safe_goal && goal.has_point(Vector2(p.x,p.z)) && p.y>=top+.01f && p.y<top+.09f;
            solid[index(x,y,z)] = p.y < floor_cache[z*nx+x] || roof || header || obstruction || goal_roof;
        }
        valve_faces.clear(); valve_closed.assign(safe_goal ? total : 0,0);
        if (safe_goal) {
            std::vector<Rect2> receivers{goal};
            if (collection_index>=0) receivers.push_back(sources[collection_index].bounds);
            for (const Rect2 &receiver:receivers) {
            int z=std::max(1,std::min(nz-2,int(std::round((receiver.position.y-origin.z)/cell_size))));
            for (int y=1;y<ny-1;++y) for (int x=1;x<nx-1;++x) {
                int i=index(x,y,z); float wx=origin.x+(x+.5f)*cell_size;
                if (wx>receiver.position.x && wx<receiver.get_end().x && !solid[i] && !solid[i-nx]) valve_faces.push_back(i);
            }
        }
        }
        for (int y = 1; y < ny - 1; ++y) for (int z = 1; z < nz - 1; ++z) for (int x = 1; x < nx - 1; ++x) {
            int i = index(x,y,z); vertical_wall[i] = solid[i] || solid[i-1] || solid[i+1] || solid[i-nx] || solid[i+nx];
        }
        for (auto &source:sources) {
            const auto &r=source.bounds; source.cells.clear();
            for (int y=1;y<ny-1;++y) for (int z=1;z<nz-1;++z) for (int x=1;x<nx-1;++x) {
                Vector3 p=origin+Vector3(x+.5f,y+.5f,z+.5f)*cell_size;
                if (!solid[index(x,y,z)] && p.x>=r.position.x && p.x<=r.get_end().x && std::abs(p.z-r.get_end().y)<.035f && p.y>=source.floor && p.y<=source.floor+.35f) source.cells.push_back(index(x,y,z));
            }
        }
        for (auto &field : faces) {
            field.velocity.assign(total,0); field.before.assign(total,0); field.weight.assign(total,0); field.valid.assign(total,0); field.touched.clear();
        }
        terrain_solid=solid; dynamic_cells.clear();
        surface_field.clear(); surface_floor.clear(); surface_touched.clear(); surface_cells.clear();
        surface_origin=Vector3(-3.6f,-1.4f,-5.6f); SX=122; SZ=188; SY=112;
        if (bounds.position.x< -2.95f || bounds.get_end().x>2.95f || bounds.position.y< -4.9f || bounds.get_end().y>4.9f) {
            surface_origin=Vector3(std::floor((bounds.position.x-.4f)/SURFACE_CELL)*SURFACE_CELL,std::floor((lowest_floor-.25f)/SURFACE_Y)*SURFACE_Y,std::floor((bounds.position.y-.4f)/SURFACE_CELL)*SURFACE_CELL);
            SX=int(std::ceil((bounds.get_end().x+.4f-surface_origin.x)/SURFACE_CELL))+2;
            SZ=int(std::ceil((bounds.get_end().y+.4f-surface_origin.z)/SURFACE_CELL))+2;
            SY=int(std::ceil((top+.25f-surface_origin.y)/SURFACE_Y))+2;
        }
        SLICE=SX*SZ; TOTAL=SLICE*SY;
        reset();
    }
    void reset() {
        clear_grid(); positions.resize(count); velocities.assign(count,Vector3()); active.assign(count,1);
        over_rim.assign(count,0); escaped.assign(count,0); through_void.assign(count,0); loss_reason.assign(count,0); spill_points.clear();
        captured.assign(count,0); bank_captured.assign(count,0); initial_source.assign(count,-1); secured=0;
        for (int i:particle_cells) particle_heads[i]=-1;
        particle_cells.clear(); capillary_pairs.clear();
        for (int i:valve_faces) valve_closed[i]=0;
        int begin=0; float cumulative=0;
        for (const auto &source:sources) {
            cumulative+=source.fill; int end=std::min(count,int(std::round(cumulative*count))), amount=end-begin;
            if (amount<=0) continue;
            Rect2 water=source.bounds.grow(-radius-.002f);
            if (sources.size()>1) water.size.y-=.06f;
            int columns=std::max(1,int(std::round(water.size.x/spacing))), rows=std::max(1,int(std::round(water.size.y/spacing)));
            int layers=std::max(1,int(std::ceil(float(amount)/(columns*rows)))),slots=columns*rows*layers;
            float height=amount*spacing*spacing*spacing/(water.size.x*water.size.y);
            for (int i=begin;i<end;++i) {
                int slot=int(int64_t(i-begin)*slots/amount),x=slot%columns,z=(slot/columns)%rows,y=slot/(columns*rows);
                float px=water.position.x+(x+.5f)*water.size.x/columns,pz=water.position.y+(z+.5f)*water.size.y/rows;
                positions[i]=Vector3(px,floor_height(Vector2(px,pz))+std::max(radius,(y+.5f)*height/layers),pz);
                initial_source[i]=int(&source-sources.data());
            }
            begin=end;
        }
        reset_phases();
        for (auto &source:sources) set_source_opening(source.id,0); gate_controlled = false;
        fraction = held = 0; lost = delivered = lost_without_rim = lost_in_void = 0; completed = false; reservoir_open = false; maximum_divergence = 0; pressure_steps = 0;
        liquid_volume = count * spacing * spacing * spacing;
    }
    void step(double delta, Vector2 tilt) {
        if (completed || count < 1 || delta <= 0) return;
        advance(delta, tilt);
    }
    void settle(double delta, Vector2 tilt) {
        if (count < 1 || delta <= 0) return;
        advance(delta, tilt);
    }
    void advance(double delta, Vector2 tilt) {
        if (!gate_controlled) set_gate_opening(1);
        float elapsed = float(std::min(delta, 1. / 30.));
        float duration = elapsed * flow_speed;
        tilt = tilt.length_squared() > 1 ? tilt.normalized() : tilt;
        Vector3 gravity = Vector3(tilt.x * .60f, -1, tilt.y * .60f).normalized() * 9.81f;
        // Scale gameplay time without adding gravity or kinetic energy.
        // Keep each advection step below one grid cell at maximum speed.
        float maximum_dt = std::min(.02f, .90f * cell_size / max_speed);
        int steps = std::max(1,int(std::ceil(duration / maximum_dt - 1e-5f)));
        float dt = duration / steps;
        spill_points.clear();
        advance_temperature(duration);
        for (int i = 0; i < steps; ++i) substep(dt,gravity);
        delivered = 0;
        for (int i = 0; i < count; ++i) if (active[i]) {
            auto p = positions[i]; Vector2 xz(p.x,p.z);
            // The vessel is its full physical footprint up to the real rim.
            // A shallow arbitrary height cutoff loses captured water when
            // gravity piles it against the wall.
            // A rigid block straddling the intake is not safely delivered yet.
            // Wait for the whole body to enter and engage its physical latch.
            bool admitted=!(safe_goal && goal_phase==ICE) || captured[i];
            if (admitted && phases[i]==goal_phase && goal.has_point(xz) && p.y >= floor_height(xz) && p.y < top) ++delivered;
        }
        fraction = float(delivered) / count; held = fraction >= required ? held + elapsed : 0; completed = held >= hold_seconds;
        liquid_volume = (count - lost) * spacing * spacing * spacing;
    }
    void set_gate_opening(double amount) { if (!sources.empty()) set_source_opening(sources[0].id,amount); }
    void set_source_opening(StringName id,double amount) {
        gate_controlled=true;
        for (auto &source:sources) if (source.id==id) {
            source.opening=clampf(float(amount),0,1);
            float eased=source.opening*source.opening*(3-2*source.opening);
            source.lower=source.floor+.40f*eased;
            if (&source==&sources[0]) { gate_fraction=source.opening; gate_lower=source.lower; reservoir_open=source.opening>=.999f; }
            for (int i:source.cells) {
                solid[i]=origin.y+(i/plane+.5f)*cell_size>=source.lower;
                if (!terrain_solid.empty()) terrain_solid[i]=solid[i];
            }
            const int offsets[5]={0,-1,1,-nx,nx};
            for (int i:source.cells) for (int offset:offsets) {
                int k=i+offset;
                vertical_wall[k]=solid[k] || solid[k-1] || solid[k+1] || solid[k-nx] || solid[k+nx];
            }
        }
    }
    Dictionary get_state() const {
        PackedVector3Array p,v; PackedByteArray a; p.resize(count); v.resize(count); a.resize(count);
        if (count) { std::copy(positions.begin(),positions.end(),p.ptrw()); std::copy(velocities.begin(),velocities.end(),v.ptrw()); std::copy(active.begin(),active.end(),a.ptrw()); }
        Dictionary d; d["positions"] = p; d["velocities"] = v; d["active"] = a; d["lost"] = lost;
        d["delivered"] = delivered; d["remaining"] = count - lost - delivered; d["lost_without_rim"] = lost_without_rim;
        d["lost_in_void"] = lost_in_void;
        d["secured"] = secured;
        Dictionary fills;
        for (const auto &source:sources) {
            int amount=0;
            for (int i=0;i<count;++i) if (active[i] && source.bounds.has_point(Vector2(positions[i].x,positions[i].z))) ++amount;
            fills[source.id]=amount;
        }
        d["source_fill"]=fills;
        append_phase_state(d);
        PackedVector3Array spills;
        for (auto point : spill_points) spills.push_back(point);
        d["spills"] = spills;
        d["fraction"] = fraction; d["held"] = held; d["completed"] = completed;
        d["divergence"] = maximum_divergence; d["cells"] = int(liquid_cells.size()); d["pressure_steps"] = pressure_steps; d["volume"] = liquid_volume;
        return d;
    }
    Dictionary build_surface() { return make_surface(LIQUID); }
    Dictionary build_ice_surface() { return make_surface(ICE); }
    void set_particle_enthalpy(int i,double value) { ERR_FAIL_INDEX(i,count); enthalpy[i]=float(value); update_phase(i); if (ice_dirty) rebuild_ice(); }
    void set_particle_state(int i, Vector3 p, Vector3 v) {
        ERR_FAIL_INDEX(i,count); positions[i]=p; velocities[i]=v;
        if (phases[i]==ICE) ice_dirty=true;
        if (captured[i]) { captured[i]=0; --secured; }
        if (!active[i]) { active[i]=1; --lost; if (loss_reason[i]==2) --lost_in_void; if (loss_reason[i]==3) --lost_without_rim; }
        over_rim[i]=p.y>=top-radius; through_void[i]=0; loss_reason[i]=0; escaped[i]=0;
    }
};

void initialize_hydrologic(ModuleInitializationLevel level) { if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<NativeLiquidSolver>(); }
void uninitialize_hydrologic(ModuleInitializationLevel) {}
extern "C" {
GDExtensionBool GDE_EXPORT hydrologic_library_init(GDExtensionInterfaceGetProcAddress proc, GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject object(proc,library,initialization);
    object.register_initializer(initialize_hydrologic); object.register_terminator(uninitialize_hydrologic);
    object.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE); return object.init();
}
}
