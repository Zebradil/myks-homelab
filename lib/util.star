# This file contains various utility functions.

load("@ytt:sha256", "sha256")
load("@ytt:struct", "struct")
load("@ytt:json", "json")

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

# Calculate the sha256 of a structure.
def checksum(s):
    return sha256.sum(json.encode(s))
end


util = struct.make(
    map_to_envs=map_to_envs,
    checksum=checksum,
)
