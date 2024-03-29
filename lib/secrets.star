load("@ytt:struct", "struct")

# Builds an ArgoCD Vault Plugin placeholder for retrieving a secret from a sops file.
# Args:
#   name: The name of the sops file (without the .sops.yaml extension).
#   key: The key in the sops file to retrieve.
#   filter: An optional filter to apply to the value after it is decrypted.
# Returns:
#   A string that can be used as a placeholder in the ArgoCD Vault Plugin.
def sops(name, key, filter=""):
    if filter:
        tail = " | " + filter
    else:
        tail = ""
    end
    return "<path:static/{}.sops.yaml#{}{}>".format(name, key, tail)
end

# Builds an ArgoCD Vault Plugin placeholder for retrieving a secret from a sops file.
# Similar to the sops function, but allows for nested keys.
# It automatically uses the correct filters to extract the nested key.
# Args:
#   name: The name of the sops file (without the .sops.yaml extension).
#   key: The key in the sops file to retrieve.
#   filter: An optional filter to apply to the value after it is decrypted.
# Returns:
#   A string that can be used as a placeholder in the ArgoCD Vault Plugin.
def sopsy(name, key, filter=""):
    parts = key.split(".")
    if len(parts) > 1:
        key = parts[0]
        filters = [
            "yamlParse",
            "jsonPath {{{}}}".format(".".join(parts[1:])),
        ]
        if filter != "":
            filters.append(filter)
        end
        filter = " | ".join(filters)
    end
    return sops(name, key, filter)
end

sec = struct.make(
    sops=sops,
    sopsy=sopsy,
)
