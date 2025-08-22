load("@ytt:assert", "assert")
load("@ytt:struct", "struct")

def get_path(source_cfg, source_name):
  kind = source_cfg.kind if "kind" in source_cfg else "charts"
  return "{}/{}".format(kind, source_name)
end

def get_source(proto_cfg, source_name, context):
  if source_name not in proto_cfg.sources:
    assert.fail("unknown source '{}'".fromat(source_name))
  end
  source_cfg = proto_cfg.sources[source_name]
  overrides = proto_cfg.sourceOverrides
  if not overrides or source_name not in overrides:
    return source_cfg
  end
  override = get_override(overrides[source_name], context)
  if override:
    return struct.encode(merge_dicts(
      struct.decode(source_cfg),
      struct.decode(override),
    ))
  end
  return source_cfg
end

def get_override(overrides, context):
  for override in overrides:
    if check_context(context, override["if"]):
      return override.then
    end
  end
  return None
end

def check_context(context, conditions):
  for key in conditions:
    value = conditions[key]
    if key not in context or context[key] != value:
      return False
    end
  end
  return True
end

def merge_dicts(dict1, dict2):
  for key, value in dict2.items():
    if type(value) == "dict" and key in dict1:
      dict1[key] = merge_dicts(dict1[key], value)
    else:
      dict1[key] = value
    end
  end
  return dict1
end

lib = struct.make(
  get_path=get_path,
  get_source=get_source,
)
