# This file contains various utility functions.

load("@ytt:struct", "struct")

# Convert a map to a list of env vars.
def map_to_envs(m):
    envs = []
    for k in m:
        envs.append({
            "name": k,
            "value": str(m[k]),
        })
    end
    return envs
end


util = struct.make(map_to_envs=map_to_envs)
