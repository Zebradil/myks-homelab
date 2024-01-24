load("@ytt:struct", "struct")

def sops(name, key, filter=""):
    if filter:
        tail = " | " + filter
    else:
        tail = ""
    end
    return "<path:static/{}.sops.yaml#{}{}>".format(name, key, tail)
end

sec = struct.make(sops=sops)
