CLUSTER_RESOURCES = set([
    "CustomResourceDefinition",
    "MutatingWebhookConfiguration",
    "Namespace",
    "Node",
    "PersistentVolume",
    "PriorityClass",
    "StorageClass",
    "ValidatingWebhookConfiguration",
    "VolumeAttachment",
])

def is_namespaced(resource):
    if resource["kind"].startswith("Cluster"):
        return False
    end
    if resource["kind"] in CLUSTER_RESOURCES:
        return False
    end
    return True
end
