// Hydrologic: incompressible 3D MAC / FLIP water with a particle free surface.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
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
struct FaceGrid {
    std::vector<float> velocity, before, weight;
    std::vector<uint8_t> valid;
    std::vector<int> touched;
};
}

class NativeLiquidSolver : public RefCounted {
    GDCLASS(NativeLiquidSolver, RefCounted)
    std::vector<Rect2> floors;
    std::vector<float> elevations;
    std::vector<Tile> tiles;
    std::vector<std::array<float, 6>> walls;
    Rect2 bounds, reservoir, goal;
    float top = 1.05f, base = -.56f, spacing = .038f, radius = .017f;
    float cell_size = .07f, mass_density = 1000, viscosity = .000001f;
    float drag = .015f, max_speed = 3, flip_ratio = .95f;
    float surface_tension = .072f;
    float required = .8f, hold_seconds = .75f, fraction = 0, held = 0;
    float maximum_divergence = 0, liquid_volume = 0;
    int count = 0, lost = 0, nx = 0, ny = 0, nz = 0, plane = 0, total = 0;
    int pressure_steps = 0;
    bool completed = false, reservoir_open = false, gate_controlled = false;
    float gate_fraction = 0, gate_lower = .42f;
    std::vector<int> gate_cells;
    Vector3 origin;
    std::vector<Vector3> positions, velocities;
    std::vector<uint8_t> active, solid, vertical_wall;
    std::vector<int> liquid_id, liquid_cells;
    std::vector<int> marker_count;
    std::vector<float> capillary_color;
    std::vector<Vector3> capillary_normal;
    std::vector<int> capillary_cells;
    std::vector<uint8_t> capillary_mark;
    std::array<FaceGrid, 3> faces;
    std::vector<float> pressure, rhs, residual, direction, preconditioned, product;
    std::vector<int> diagonal;

    int index(int x, int y, int z) const { return y * plane + z * nx + x; }
    bool in_grid(int x, int y, int z) const {
        return x >= 0 && y >= 0 && z >= 0 && x < nx && y < ny && z < nz;
    }
    bool is_solid(int x, int y, int z) const {
        return !in_grid(x, y, z) || solid[index(x, y, z)];
    }
    float floor_height(Vector2 point) const {
        if (!bounds.has_point(point)) return -std::numeric_limits<float>::infinity();
        float height = top;
        for (size_t i = 0; i < floors.size(); ++i)
            if (floors[i].has_point(point)) height = std::min(height, elevations[i]);
        return height;
    }
    bool face_blocked(int component, int x, int y, int z) const {
        if (!in_grid(x, y, z)) return true;
        return is_solid(x, y, z) || is_solid(x - (component == 0), y - (component == 1), z - (component == 2));
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
    void scatter(Vector3 point, Vector3 velocity) {
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
                field.weight[i] += weight; field.velocity[i] += weight * velocity[component];
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
                if (id >= 0) value -= input[id];
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
            for (int offset : neighbors) if (!solid[cell + offset]) ++d;
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
                if (left < 0 || solid[i] || solid[left]) { field.velocity[i] = 0; continue; }
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
        Vector2 xz(point.x, point.z);
        float floor = floor_height(xz);
        if (std::isfinite(floor) && point.y < floor + radius && previous.y >= floor + radius - .0001f) point.y = floor + radius;
        Vector3 q = (point - origin) / cell_size;
        int x = int(std::floor(q.x)), y = int(std::floor(q.y)), z = int(std::floor(q.z));
        bool needs_walls = in_grid(x, y, z) && vertical_wall[index(x, y, z)];
        if (needs_walls) for (const auto &tile : tiles) {
            const Rect2 &r = tile.rectangle;
            if (point.y >= tile.height + radius || point.y < base - radius || !r.grow(radius).has_point(Vector2(point.x, point.z))) continue;
            point = collide_box(point, Vector3(r.position.x, base, r.position.y), Vector3(r.get_end().x, tile.height, r.get_end().y), radius);
        }
        float roof = top + .07f;
        if (reservoir.grow(radius).has_point(Vector2(point.x, point.z)) && std::abs(point.y - roof) < .15f)
            point = collide_box(point, Vector3(reservoir.position.x, roof, reservoir.position.y), Vector3(reservoir.get_end().x, roof + .04f, reservoir.get_end().y), radius);
        if (gate_lower < elevations[0] + .35f && reservoir.grow(radius).has_point(Vector2(point.x,point.z)) && std::abs(point.z - reservoir.get_end().y) < .08f) {
            point = collide_box(point, Vector3(reservoir.position.x,gate_lower,reservoir.get_end().y - .025f), Vector3(reservoir.get_end().x,elevations[0] + .35f,reservoir.get_end().y + .025f), radius);
        }
        float port = elevations[0] + .35f;
        if (reservoir.grow(radius).has_point(Vector2(point.x,point.z)) && std::abs(point.z - reservoir.get_end().y) < .08f && point.y > port - radius) {
            point = collide_box(point, Vector3(reservoir.position.x,port,reservoir.get_end().y - .025f), Vector3(reservoir.get_end().x,top + .11f,reservoir.get_end().y + .025f), radius);
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
    void substep(float dt, Vector3 gravity) {
        clear_grid();
        for (int i = 0; i < count; ++i) if (active[i]) scatter(positions[i], velocities[i]);
        for (int component = 0; component < 3; ++component) {
            FaceGrid &field = faces[component];
            for (int i : field.touched) field.velocity[i] /= std::max(field.weight[i], 1e-12f);
            extrapolate(component, 2);
            for (int i : field.touched) field.before[i] = field.velocity[i];
            for (int i : field.touched) field.velocity[i] += gravity[component] * dt;
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
        for (int i = 0; i < count; ++i) if (active[i]) {
            Vector3 previous = positions[i], pic = sample_velocity(previous);
            Vector3 flip = velocities[i] + pic - sample_velocity(previous,true);
            // Bound unresolved velocity noise; coherent grid motion is kept.
            Vector3 residual_velocity=limited(flip-pic,.40f);
            Vector3 velocity=limited((pic+residual_velocity*flip_ratio)*std::exp(-drag*dt),max_speed);
            Vector3 midpoint = previous + sample_velocity(previous) * (.5f * dt);
            Vector3 candidate = previous + limited(sample_velocity(midpoint), max_speed) * dt;
            // Below grid resolution, detached spray travels ballistically.
            // Projecting one marker as a full liquid cell invents pressure and
            // gives a droplet spurious impulses at wall and floor contacts.
            Vector3 q = (previous - origin) / cell_size;
            int x = int(std::floor(q.x)), y = int(std::floor(q.y)), z = int(std::floor(q.z));
            int nearby = 0;
            if (in_grid(x,y,z)) {
                int cell = index(x,y,z);
                for (int offset : {0,-1,1,-nx,nx,-plane,plane})
                    if (cell + offset >= 0 && cell + offset < total) nearby += marker_count[cell + offset];
            }
            if (nearby < 4) {
                velocity = limited((velocities[i] + gravity * dt) * std::exp(-drag * dt), max_speed);
                candidate = previous + (velocities[i] + velocity) * (.5f * dt);
            }
            Vector3 point = constrain(candidate, previous), contact = candidate - point;
            if (contact.x * velocity.x > 0) velocity.x = 0;
            if (contact.y * velocity.y > 0) velocity.y = 0;
            if (contact.z * velocity.z > 0) velocity.z = 0;
            positions[i] = point; velocities[i] = velocity;
            if (point.y < base - .65f || !bounds.grow(.42f).has_point(Vector2(point.x, point.z))) { active[i] = 0; ++lost; }
        }

    }

    // Sparse weighted-centroid surface reconstruction. Reflected samples
    // complete support at solid contacts; the vertical grid follows each step.
    static constexpr int SX = 122, SZ = 188, SY = 112, SLICE = SX * SZ, TOTAL = SLICE * SY;
    static constexpr float SURFACE_CELL = .06f, SURFACE_Y = .035f, KERNEL = .11f, ISO = .5f;
    const Vector3 surface_origin = Vector3(-3.6f, -1.4f, -5.6f);
    std::vector<float> surface_field, surface_floor;
    std::vector<Vector3> surface_gradient, surface_vertices, surface_normals;
    std::vector<uint8_t> surface_flags;
    std::vector<int> surface_touched, surface_cells;
    void splat_surface(Vector3 p, float weight) {
        Vector3 c = (p - surface_origin) / Vector3(SURFACE_CELL,SURFACE_Y,SURFACE_CELL); float r2 = KERNEL * KERNEL;
        const int offsets[8] = {0, -1, -SX, -SX - 1, -SLICE, -SLICE - 1, -SLICE - SX, -SLICE - SX - 1};
        for (int y = std::max(1, int(std::floor(c.y)) - 4); y < std::min(SY - 1, int(std::ceil(c.y)) + 5); ++y) {
            float wy = surface_origin.y + y * SURFACE_Y, dy = wy - p.y;
            if (dy * dy >= r2) continue;
            for (int z = std::max(1, int(std::floor(c.z)) - 2); z < std::min(SZ - 1, int(std::ceil(c.z)) + 3); ++z) {
                float dz = surface_origin.z + z * SURFACE_CELL - p.z, yz2 = dy * dy + dz * dz;
                if (yz2 >= r2) continue;
                for (int x = std::max(1, int(std::floor(c.x)) - 2); x < std::min(SX - 1, int(std::ceil(c.x)) + 3); ++x) {
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
        float height = floor_height(Vector2(point.x, point.z));
        if (!std::isfinite(height) || point.y >= height + .001f) return point;
        if (height - point.y < SURFACE_Y) { point.y = height + .001f; return point; }
        if (point.y >= top) return point;
        Vector2 nearest(point.x, point.z); float best = 1e20f;
        for (size_t i = 0; i < floors.size(); ++i) if (elevations[i] < point.y + .001f) {
            Rect2 r = floors[i].grow(-.001f); auto end = r.get_end();
            Vector2 candidate(clampf(point.x, r.position.x, end.x), clampf(point.z, r.position.y, end.y));
            float distance = candidate.distance_squared_to(Vector2(point.x, point.z));
            if (distance < best) { nearest = candidate; best = distance; }
        }
        point.x = nearest.x; point.z = nearest.y; return point;
    }
    Dictionary make_surface() {
        if (surface_field.empty()) {
            surface_field.assign(TOTAL, 0); surface_gradient.assign(TOTAL, Vector3()); surface_flags.assign(TOTAL, 0); surface_floor.resize(SLICE);
            for (int z = 0; z < SZ; ++z) for (int x = 0; x < SX; ++x) surface_floor[z * SX + x] = floor_height(Vector2(surface_origin.x + x * SURFACE_CELL, surface_origin.z + z * SURFACE_CELL));
        }
        for (int i : surface_touched) { surface_field[i] = 0; surface_gradient[i] = Vector3(); }
        for (int i : surface_cells) surface_flags[i] = 0;
        surface_touched.clear(); surface_cells.clear(); surface_vertices.clear(); surface_normals.clear();
        float volume = spacing * spacing * spacing;
        float weight = 315 * volume / (64 * 3.14159265359f * KERNEL * KERNEL * KERNEL);
        for (int i = 0; i < count; ++i) if (active[i]) {
            auto p = positions[i];
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
            float distance=point.distance_to(mean);
            surface_field[i]=clampf(.5f+(spacing*.90f-distance)/KERNEL,0,1);
        }
        for (int i : surface_touched) {
            surface_gradient[i]=Vector3((surface_field[i+1]-surface_field[i-1])/(2*SURFACE_CELL),(surface_field[i+SLICE]-surface_field[i-SLICE])/(2*SURFACE_Y),(surface_field[i+SX]-surface_field[i-SX])/(2*SURFACE_CELL));
        }
        const int corners[8] = {0, 1, SX + 1, SX, SLICE, SLICE + 1, SLICE + SX + 1, SLICE + SX};
        const int tets[6][4] = {{0,5,1,6},{0,1,2,6},{0,2,3,6},{0,3,7,6},{0,7,4,6},{0,4,5,6}};
        const int edges[6][2] = {{0,1},{1,2},{2,0},{0,3},{1,3},{2,3}};
        const int tris[16][7] = {{-1},{0,3,2,-1},{0,1,4,-1},{1,4,2,2,4,3,-1},{1,2,5,-1},{0,3,5,0,5,1,-1},{0,2,5,0,5,4,-1},{5,4,3,-1},{3,4,5,-1},{4,5,0,5,2,0,-1},{1,5,0,5,3,0,-1},{5,2,1,-1},{3,4,2,2,4,1,-1},{4,1,0,-1},{2,3,0,-1},{-1}};
        float values[8]; Vector3 points[8], normals[8], ep[6], en[6];
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
                    ep[e] = surface_contact(points[a].lerp(points[b], t));
                    Vector3 n = normals[a].lerp(normals[b], t); en[e] = n.length_squared() > 1e-8f ? n.normalized() : Vector3(0,1,0);
                }
                for (int t = 0; tris[m][t] >= 0; t += 3) {
                    int a = tris[m][t], b = tris[m][t + 1], c = tris[m][t + 2];
                    if ((ep[b] - ep[a]).cross(ep[c] - ep[a]).dot(en[a] + en[b] + en[c]) > 0) std::swap(b,c);
                    for (int e : {a,b,c}) { surface_vertices.push_back(ep[e]); surface_normals.push_back(en[e]); }
                }
            }
        }
        // Sparse spray has too little kernel support for an isosurface.
        // Keep those real markers visible as small 3D droplets.
        const Vector3 droplet_axes[6] = {Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,1,0),Vector3(0,-1,0),Vector3(0,0,1),Vector3(0,0,-1)};
        const int droplet_faces[8][3] = {{2,0,4},{2,4,1},{2,1,5},{2,5,0},{3,4,0},{3,1,4},{3,5,1},{3,0,5}};
        for (int i = 0; i < count; ++i) if (active[i]) {
            Vector3 q = (positions[i] - surface_origin) / Vector3(SURFACE_CELL,SURFACE_Y,SURFACE_CELL);
            int x = int(std::round(q.x)), y = int(std::round(q.y)), z = int(std::round(q.z));
            if (x <= 0 || y <= 0 || z <= 0 || x >= SX-1 || y >= SY-1 || z >= SZ-1) continue;
            if (surface_field[y * SLICE + z * SX + x] >= ISO * .75f) continue;
            for (const auto &triangle : droplet_faces) for (int k : {0,1,2}) {
                Vector3 normal = droplet_axes[triangle[k]];
                surface_vertices.push_back(positions[i] + normal * radius);
                surface_normals.push_back(normal);
            }
        }
        PackedVector3Array vertices_out, normals_out;
        vertices_out.resize(surface_vertices.size()); normals_out.resize(surface_normals.size());
        if (!surface_vertices.empty()) {
            std::copy(surface_vertices.begin(), surface_vertices.end(), vertices_out.ptrw());
            std::copy(surface_normals.begin(), surface_normals.end(), normals_out.ptrw());
        }
        Dictionary result; result["vertices"] = vertices_out; result["normals"] = normals_out; return result;
    }

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure", "configuration"), &NativeLiquidSolver::configure);
        ClassDB::bind_method(D_METHOD("reset"), &NativeLiquidSolver::reset);
        ClassDB::bind_method(D_METHOD("step", "delta", "tilt"), &NativeLiquidSolver::step);
        ClassDB::bind_method(D_METHOD("set_gate_opening", "amount"), &NativeLiquidSolver::set_gate_opening);
        ClassDB::bind_method(D_METHOD("get_state"), &NativeLiquidSolver::get_state);
        ClassDB::bind_method(D_METHOD("build_surface"), &NativeLiquidSolver::build_surface);
        ClassDB::bind_method(D_METHOD("set_particle_state", "index", "position", "velocity"), &NativeLiquidSolver::set_particle_state);
    }
public:
    void configure(const Dictionary &cfg) {
        floors.clear(); elevations.clear(); tiles.clear(); walls.clear();
        Array fs = cfg["regions"], ts = cfg["tiles"], ws = cfg["walls"];
        PackedFloat32Array heights = cfg["elevations"];
        for (int i = 0; i < fs.size(); ++i) { floors.push_back(Rect2(fs[i])); elevations.push_back(i < heights.size() ? heights[i] : 0); }
        for (int i = 0; i < ts.size(); ++i) { Dictionary t = ts[i]; tiles.push_back(Tile{Rect2(t["bounds"]), float(t["height"])}); }
        for (int i = 0; i < ws.size(); ++i) { PackedFloat32Array w = ws[i]; std::array<float,6> a{}; for (int j = 0; j < 6; ++j) a[j] = w[j]; walls.push_back(a); }
        bounds = cfg["bounds"]; reservoir = cfg.has("reservoir") ? Rect2(cfg["reservoir"]) : Rect2(cfg["spawn"]); goal = cfg["goal"];
        count = int(cfg["count"]); top = float(cfg["top"]); base = float(cfg["base"]); spacing = float(cfg["spacing"]); radius = float(cfg["radius"]);
        mass_density = float(cfg["rho"]); max_speed = float(cfg["max_speed"]); drag = float(cfg["drag"]); viscosity = float(cfg["viscosity"]);
        surface_tension = cfg.has("surface_tension") ? float(cfg["surface_tension"]) : .072f;
        required = float(cfg["required"]); hold_seconds = float(cfg["hold"]);
        ERR_FAIL_COND(count < 1 || count > 32768 || spacing <= 0 || floors.empty());
        origin = Vector3(std::floor((bounds.position.x - .49f) / cell_size) * cell_size, std::floor((base - .7f) / cell_size) * cell_size, std::floor((bounds.position.y - .49f) / cell_size) * cell_size);
        nx = int(std::ceil((bounds.get_end().x + .49f - origin.x) / cell_size)) + 2;
        nz = int(std::ceil((bounds.get_end().y + .49f - origin.z) / cell_size)) + 2;
        ny = int(std::ceil((top + 1.2f - origin.y) / cell_size)) + 2;
        plane = nx * nz; total = plane * ny;
        solid.assign(total, 1); vertical_wall.assign(total, 1); liquid_id.assign(total, -1); marker_count.assign(total, 0); liquid_cells.clear();
        capillary_color.assign(total,0); capillary_normal.assign(total,Vector3()); capillary_mark.assign(total,0); capillary_cells.clear();
        for (int y = 1; y < ny - 1; ++y) for (int z = 1; z < nz - 1; ++z) for (int x = 1; x < nx - 1; ++x) {
            Vector3 p = origin + Vector3(x + .5f, y + .5f, z + .5f) * cell_size;
            bool roof = reservoir.has_point(Vector2(p.x,p.z)) && p.y >= top + .07f && p.y < top + .11f;
            bool header = p.x >= reservoir.position.x && p.x <= reservoir.get_end().x && std::abs(p.z - reservoir.get_end().y) < .035f && p.y > elevations[0] + .35f && p.y < top + .11f;
            solid[index(x,y,z)] = p.y < floor_height(Vector2(p.x,p.z)) || roof || header;
        }
        for (int y = 1; y < ny - 1; ++y) for (int z = 1; z < nz - 1; ++z) for (int x = 1; x < nx - 1; ++x) {
            int i = index(x,y,z); vertical_wall[i] = solid[i] || solid[i-1] || solid[i+1] || solid[i-nx] || solid[i+nx];
        }
        gate_cells.clear();
        for (int y = 1; y < ny - 1; ++y) for (int z = 1; z < nz - 1; ++z) for (int x = 1; x < nx - 1; ++x) {
            Vector3 p = origin + Vector3(x+.5f,y+.5f,z+.5f) * cell_size;
            if (!solid[index(x,y,z)] && p.x >= reservoir.position.x && p.x <= reservoir.get_end().x && std::abs(p.z - reservoir.get_end().y) < .035f && p.y >= elevations[0] && p.y <= elevations[0] + .35f) gate_cells.push_back(index(x,y,z));
        }
        for (auto &field : faces) {
            field.velocity.assign(total,0); field.before.assign(total,0); field.weight.assign(total,0); field.valid.assign(total,0); field.touched.clear();
        }
        surface_field.clear(); surface_floor.clear(); surface_touched.clear(); surface_cells.clear();
        reset();
    }
    void reset() {
        clear_grid(); positions.resize(count); velocities.assign(count,Vector3()); active.assign(count,1);
        Rect2 water = reservoir.grow(-radius - .002f);
        int columns = std::max(1,int(std::round(water.size.x / spacing))), rows = std::max(1,int(std::round(water.size.y / spacing)));
        int layers = std::max(1,int(std::ceil(float(count) / (columns * rows)))), slots = columns * rows * layers;
        float height = count * spacing * spacing * spacing / (water.size.x * water.size.y);
        for (int i = 0; i < count; ++i) {
            int slot = int(int64_t(i) * slots / count), x = slot % columns, z = (slot / columns) % rows, y = slot / (columns * rows);
            float px = water.position.x + (x + .5f) * water.size.x / columns, pz = water.position.y + (z + .5f) * water.size.y / rows;
            float py = floor_height(Vector2(px,pz)) + std::max(radius, (y + .5f) * height / layers);
            positions[i] = Vector3(px,py,pz);
        }
        set_gate_opening(0); gate_controlled = false;
        fraction = held = 0; lost = 0; completed = false; reservoir_open = false; maximum_divergence = 0; pressure_steps = 0;
        liquid_volume = count * spacing * spacing * spacing;
    }
    void step(double delta, Vector2 tilt) {
        if (completed || count < 1 || delta <= 0) return;
        if (!gate_controlled) set_gate_opening(1);
        float duration = float(std::min(delta, 1. / 30.));
        tilt = tilt.length_squared() > 1 ? tilt.normalized() : tilt;
        Vector3 gravity = Vector3(tilt.x * .5f, -1, tilt.y * .5f).normalized() * 9.81f;
        int steps = std::max(1,int(std::ceil(duration * 60.f - 1e-5f)));
        float dt = duration / steps;
        for (int i = 0; i < steps; ++i) substep(dt,gravity);
        int delivered = 0;
        for (int i = 0; i < count; ++i) if (active[i]) {
            auto p = positions[i]; Vector2 xz(p.x,p.z);
            if (goal.has_point(xz) && p.y < floor_height(xz) + .34f) ++delivered;
        }
        fraction = float(delivered) / count; held = fraction >= required ? held + duration : 0; completed = held >= hold_seconds;
        liquid_volume = (count - lost) * spacing * spacing * spacing;
    }
    void set_gate_opening(double amount) {
        gate_fraction = clampf(float(amount),0,1); gate_controlled = true;
        float eased = gate_fraction * gate_fraction * (3-2*gate_fraction);
        gate_lower = elevations[0] + .40f * eased;
        reservoir_open = gate_fraction >= .999f;
        for (int i : gate_cells) {
            int y = i / plane;
            solid[i] = origin.y + (y+.5f) * cell_size >= gate_lower;
        }
        const int offsets[5] = {0,-1,1,-nx,nx};
        for (int i : gate_cells) for (int offset : offsets) {
            int k = i + offset;
            vertical_wall[k] = solid[k] || solid[k-1] || solid[k+1] || solid[k-nx] || solid[k+nx];
        }
    }
    Dictionary get_state() const {
        PackedVector3Array p,v; PackedByteArray a; p.resize(count); v.resize(count); a.resize(count);
        if (count) { std::copy(positions.begin(),positions.end(),p.ptrw()); std::copy(velocities.begin(),velocities.end(),v.ptrw()); std::copy(active.begin(),active.end(),a.ptrw()); }
        Dictionary d; d["positions"] = p; d["velocities"] = v; d["active"] = a; d["lost"] = lost;
        d["fraction"] = fraction; d["held"] = held; d["completed"] = completed;
        d["divergence"] = maximum_divergence; d["cells"] = int(liquid_cells.size()); d["pressure_steps"] = pressure_steps; d["volume"] = liquid_volume;
        return d;
    }
    Dictionary build_surface() { return make_surface(); }
    void set_particle_state(int i, Vector3 p, Vector3 v) { ERR_FAIL_INDEX(i,count); positions[i] = p; velocities[i] = v; if (!active[i]) { active[i] = 1; --lost; } }
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
