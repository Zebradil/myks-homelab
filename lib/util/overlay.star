load("@ytt:struct", "struct")
load("/util.star", "deep_get", "deep_set", "yf_to_star")

def append_to(*keys):
  return lambda l, r: _update_via(l, r, _append_to_list, *keys)
end

def extend(*keys):
  return lambda l, r: _update_via(l, r, _extend_list, *keys)
end

def _update_via(l, r, fn, *keys):
  dst, found = deep_get(l, *keys)
  if type(dst) == "yamlfragment":
    dst = yf_to_star(dst)
  end
  if type(r) == "yamlfragment":
    r = yf_to_star(r)
  end
  return deep_set(l, fn(dst, r), *keys)
end

def _append_to_list(dst, val):
  if dst == None:
    return [val]
  else:
    return dst + [val]
  end
end

def _extend_list(dst, val):
  if dst == None:
    return val
  else:
    return dst + val
  end
end

list = struct.make(
  append_to=append_to,
  extend=extend,
)
