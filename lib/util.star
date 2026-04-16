# This file contains various utility functions.

load("@ytt:json", "json")
load("@ytt:sha256", "sha256")
load("@ytt:struct", "struct")
load("@ytt:yaml", "yaml")

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

# yget retrieves a value from a yamlfragment by key, returning a default value if the key is not present.
def yget(yamlfragment, key, default=None):
  return yamlfragment[key] if key in yamlfragment else default
end

# yamlfragment_to_dict converts a yamlfragment to a dictionary.
# This can be useful for debugging:
#   print(yamlfragment_to_dict(some_yamlfragment))
# DEPRECATED: use yf_to_star instead.
def yamlfragment_to_dict(yamlfragment):
  return yf_to_star(yamlfragment)
end

# yf_to_star converts a yamlfragment to a Star data structure.
# This can be useful for debugging:
#   print(yf_to_star(some_yamlfragment))
def yf_to_star(yamlfragment):
  return yaml.decode(yaml.encode(yamlfragment))
end

def print_yf_as_json(yamlfragment):
  print(json.encode(yf_to_star(yamlfragment), indent=2))
end

# deep_get retrieves a value from a nested dictionary using a sequence of keys.
# If any key does not exist, it returns None and a boolean indicating success.
# Example usage:
#   my_dict = {"a": {"b": {"c": 42}}}
#   value, exists = deep_get(my_dict, "a", "b", "c")
#   print(value, exists)  # Output: 42 True
#   value, exists = deep_get(my_dict, "a", "b", "d")
#   print(value, exists)  # Output: None False
def deep_get(obj, *keys):
  # Get a value from a nested dictionary using a list of keys.
  # If any key does not exist, return None.
  for key in keys:
    if type(obj) not in ["dict", "yamlfragment"] or key not in obj:
      return None, False
    end
    obj = obj[key]
  end
  return obj, True
end

# deep_check checks if a nested dictionary contains a sequence of keys.
# It returns True if all keys exist, otherwise it returns False.
# Example usage:
#   my_dict = {"a": {"b": {"c": 42}}}
#   exists = deep_check(my_dict, "a", "b", "c")
#   print(exists)  # Output: True
#   exists = deep_check(my_dict, "a", "b", "d")
#   print(exists)  # Output: False
def deep_check(obj, *keys):
  # Check if a nested dictionary contains a sequence of keys.
  # Returns True if all keys exist, False otherwise.
  value, exists = deep_get(obj, *keys)
  return exists
end

# _deep_set sets a value in a nested dictionary using a sequence of keys.
# It creates intermediate dictionaries if they do not exist.
# obj must be a dictionary, as well as all intermediate values.
# Hint: use yamlfragment_to_dict to convert yamlfragments to dictionaries.
# Example usage:
#   my_dict = {}
#   updated_dict = _deep_set(my_dict, 42, "a", "b", "c")
#   print(updated_dict)  # Output: {"a": {"b": {"c": 42}}}
def _deep_set(obj, value, *keys):
  if len(keys) == 0:
    fail("deep_set: at least one key is required")
  end
  if type(obj) != "dict":
    fail("deep_set: obj must be a dictionary")
  end
  root_obj = obj
  for key in keys[:-1]:
    if key not in obj:
      obj[key] = {}
    elif type(obj[key]) != "dict":
      fail("deep_set: intermediate value for key '%s' is not a dictionary".format(key))
    end
    obj = obj[key]
  end
  last_key = keys[-1]
  obj[last_key] = value
  return root_obj
end

# deep_set sets a value in a nested dictionary using a sequence of keys.
# It creates intermediate dictionaries if they do not exist.
# If obj is a yamlfragment, it is converted to a dictionary first.
# If value is a function, it is called with the current value and the result is used as the new value.
# Example usage:
#   my_dict = {}
#   my_dict = deep_set(my_dict, 42,               "a", "b", "c") # Returns: {"a": {"b": {"c": 42}}}
#   my_dict = deep_set(my_dict, lambda v: v/2,    "a", "b", "c") # Returns: {"a": {"b": {"c": 21}}}
#   my_dict = deep_set(my_dict, lambda v=12: v/2, "a", "b", "z") # Returns: {"a": {"b": {"c": 21, "z": 6}}}
def deep_set(obj, value, *keys):
  if type(obj) == "yamlfragment":
    obj = yamlfragment_to_dict(obj)
  end
  if type(value) == "function":
    current_value, exists = deep_get(obj, *keys)
    value = value(current_value) if exists else value()
  end
  return _deep_set(obj, value, *keys)
end

util = struct.make(
  checksum=checksum,
  deep_check=deep_check,
  deep_get=deep_get,
  deep_set=deep_set,
  map_to_envs=map_to_envs,
  yamlfragment_to_dict=yamlfragment_to_dict,
  yf_to_star=yf_to_star,
)

# vim: set sw=2 ts=2 et:
