# This module uses the @myks library, so it has to be placed directly in the root (lib/).
# Otherwise, ytt can't find the library.

load("@ytt:data", "data")
load("@ytt:struct", "struct")
load("@myks:data.lib.yaml", "env_data")

dv = data.values
# In the context of data values, data.values is empty, so we fallback to the env_data library.
if len(dv) == 0:
  dv = struct.encode(env_data)
end

def app_used(app_name):
  """
  Check if the app is defined in the current environment.
  """
  for app in dv.environment.applications:
    if app.name == app_name:
      return True
    end
  end
  return False
end

def proto_used(proto_name):
  """
  Check if the prototype is used in the current environment.
  """
  for app in dv.environment.applications:
    if app.proto == proto_name:
      return True
    end
  end
  return False
end
