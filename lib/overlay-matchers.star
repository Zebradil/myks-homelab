# This file contains helper matcher functions to use with overlays.
# Example usage:
#
#   #@ load("@ytt:overlay", "overlay")
#   #@ load("overlay-matchers.star", "matchers")
#
#   #@overlay/match by=matchers.kind_name("Deployment", "velero")
#   ---
#   metadata:
#     #! Remove the empty labels field.
#     #@overlay/match by=matchers.empty("labels")
#     #@overlay/remove
#     labels:
#   spec:
#     #! Set replicas to 13 only if replicas is set to 2.
#     #@overlay/match by=matchers.value("2")
#     replicas: 13
#     strategy:
#       #! Remove the type field if its value is Recreate.
#       #@overlay/match by=matchers.value()
#       #@overlay/remove
#       type: Recreate
#


load("@ytt:overlay", "overlay")
load("@ytt:struct", "struct")

# kind_name creates a matcher that matches a resource by kind and name.
#   Example: kind_name("Deployment", "velero")
def kind_name(kind, name):
    return overlay.subset({
        "kind": kind,
        "metadata": {
            "name": name,
        },
    })
end

# kind_name_prefix creates a matcher that matches a resource by kind and a name
# prefix.
def kind_name_prefix(kind, prefix):
    kind = overlay.subset({
        "kind": kind,
    })
    prefix_match = lambda idx, left, right: left["metadata"]["name"].startswith(prefix)

    return overlay.and_op(kind, prefix_match)
end

# value creates a matcher that matches a resource by a specific value.
#   Example: value("1.2.3") matches the node if its value is "1.2.3".
# If no value is provided, it matches by the value specified in the overlay.
#   Example: value() matches the node if its value is equal to the value specified in the overlay.
def value(val=None):
    if val == None:
        return lambda i, l, r: l == r
    end
    return lambda i, l, r: l == val
end

def empty(id_or_name=None):
    if id_or_name == None:
        return lambda i, l, r: dict(**l) == {}
    end
    return lambda i, l, r: i == id_or_name and dict(**l) == {}
end


matchers = struct.make(
    empty=empty,
    kind_name=kind_name,
    kind_name_prefix=kind_name_prefix,
    value=value,
)
