// Conservative particle redistribution for PIC/FLIP. Pressure keeps the grid
// velocity divergence free, but cannot separate coincident marker trajectories
// after a long contact with a closed tank. Regularize only overlapping liquid
// neighbours. Pair reactions preserve free momentum; there are no permanent
// bonds, extra parcels or long-range attraction.
void regularize_liquid_particles() {
    const float rest=spacing*.95f, rest2=rest*rest;
    struct NearPair { int a,b; Vector3 normal; float overlap; };
    std::vector<NearPair> pairs;
    std::vector<int> degree(count);
    std::vector<Vector3> correction(count);
    std::vector<int> parcel_cell(count,-1);
    std::vector<uint8_t> overcrowded(count,0);
    std::unordered_map<int,int> population;
    const int capacity=std::max(16,int(std::ceil(4*cell_size*cell_size*cell_size/(spacing*spacing*spacing))));
    for (int iteration=0;iteration<2;++iteration) {
        for (int cell:particle_cells) particle_heads[cell]=-1;
        particle_cells.clear(); pairs.clear();
        population.clear();
        std::fill(parcel_cell.begin(),parcel_cell.end(),-1);
        std::fill(degree.begin(),degree.end(),0);
        std::fill(correction.begin(),correction.end(),Vector3());
        for (int i=0;i<count;++i) if (active[i] && phases[i]==LIQUID) {
            Vector3 q=(positions[i]-origin)/cell_size;
            int x=int(std::floor(q.x)),y=int(std::floor(q.y)),z=int(std::floor(q.z));
            if (!in_grid(x,y,z)) continue;
            int cell=index(x,y,z);
            parcel_cell[i]=cell; ++population[cell];
            if (particle_heads[cell]<0) particle_cells.push_back(cell);
            particle_next[i]=particle_heads[cell]; particle_heads[cell]=i;
        }
        bool crowded=false;
        for (int i=0;i<count;++i) {
            overcrowded[i]=parcel_cell[i]>=0 && population[parcel_cell[i]]>=capacity;
            crowded|=overcrowded[i];
        }
        if (!crowded) break;
        for (int i=0;i<count;++i) if (active[i] && phases[i]==LIQUID) {
            Vector3 p=positions[i],lo=(p-Vector3(rest,rest,rest)-origin)/cell_size,hi=(p+Vector3(rest,rest,rest)-origin)/cell_size;
            for (int y=std::max(0,int(std::floor(lo.y)));y<=std::min(ny-1,int(std::floor(hi.y)));++y)
            for (int z=std::max(0,int(std::floor(lo.z)));z<=std::min(nz-1,int(std::floor(hi.z)));++z)
            for (int x=std::max(0,int(std::floor(lo.x)));x<=std::min(nx-1,int(std::floor(hi.x)));++x)
            for (int j=particle_heads[index(x,y,z)];j>=0;j=particle_next[j]) {
                if (j<=i || captured[i]!=captured[j]) continue;
                if (!overcrowded[i] && !overcrowded[j]) continue;
                Vector3 delta=positions[j]-p; float d2=delta.length_squared();
                if (d2>=rest2) continue;
                float distance=std::sqrt(d2); Vector3 normal;
                if (distance>1e-6f) normal=delta/distance;
                else {
                    uint32_t seed=uint32_t(i)*73856093U ^ uint32_t(j)*19349663U;
                    normal=Vector3(float(seed&1023)-511.5f,float((seed>>10)&1023)-511.5f,float((seed>>20)&1023)-511.5f).normalized();
                }
                pairs.push_back({i,j,normal,rest-distance}); ++degree[i]; ++degree[j];
            }
        }
        if (pairs.empty()) break;
        for (const auto &pair:pairs) {
            float weight=.25f;
            Vector3 shift=pair.normal*(pair.overlap*weight);
            correction[pair.a]-=shift; correction[pair.b]+=shift;
        }
        float largest=0;
        for (const auto &shift:correction) largest=std::max(largest,shift.length());
        float scale=largest>spacing*.15f ? spacing*.15f/largest:1;
        for (int i=0;i<count;++i) if (degree[i]>0) {
            Vector3 previous=positions[i];
            Vector3 candidate=previous+correction[i]*scale;
            if (!ice_bodies.empty()) candidate=project_ice(candidate,radius);
            Vector3 point=constrain(candidate,previous);
            admit_liquid(i,point);
            positions[i]=point;
            record_loss(i,previous,candidate);
        }
    }
}
