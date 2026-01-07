load("@ytt:struct", "struct")

# Builds a vals placeholder for retrieving a secret from a sops file.
# Ref: https://github.com/helmfile/vals#sops
# Args:
#   name: The name of the sops file (without the .sops.yaml extension).
#   key: The key in the sops file to retrieve.
# Returns:
#   A string that is recognized by vals as a sops secret reference.
def sops(name, key):
    return "ref+sops://static/{}.sops.yaml#/{}+".format(name, key.replace(".", "/"))
end

sec = struct.make(
    sops=sops,
)
