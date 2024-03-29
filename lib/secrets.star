load("@ytt:struct", "struct")

# Builds an ArgoCD Vault Plugin placeholder for retrieving a secret from a sops file.
# Args:
#   name: The name of the sops file (without the .sops.yaml extension).
#   key: The key in the sops file to retrieve.
#   filters: An optional list of filters to apply to the value after it is decrypted.
# Returns:
#   A string that can be used as a placeholder in the ArgoCD Vault Plugin.
def sops(name, key, filters=[]):
    filterStr = ""
    if len(filters) > 0:
        filterStr = " | " + " | ".join(filters)
    end
    return "<path:static/{}.sops.yaml#{}{}>".format(name, key, filterStr)
end

# Builds an ArgoCD Vault Plugin placeholder for retrieving a secret from a sops file.
# Similar to the sops function, but allows for nested keys.
# It automatically uses the correct filters to extract the nested key.
# Args:
#   name: The name of the sops file (without the .sops.yaml extension).
#   key: The key in the sops file to retrieve.
#   filters: An optional list of filters to apply to the value after it is decrypted.
# Returns:
#   A string that can be used as a placeholder in the ArgoCD Vault Plugin.
def sopsy(name, key, filters=[]):
    parts = key.split(".")
    if len(parts) > 1:
        key = parts[0]
        filters = ["jsonPath {{.{}}}".format(".".join(parts[1:]))] + filters
    end
    return sops(name, key, filters)
end

sec = struct.make(
    sops=sops,
    sopsy=sopsy,
)
