import json

file_path = '/tmp/ageval/config.json'
with open(file_path, 'r') as f:
    data = json.load(f)

def rename_key(obj):
    if isinstance(obj, dict):
        new_dict = {}
        for k, v in obj.items():
            new_key = "port" if k == "prot" else k
            new_dict[new_key] = rename_key(v)
        return new_dict
    elif isinstance(obj, list):
        return [rename_key(i) for i in obj]
    else:
        return obj

new_data = rename_key(data)

with open(file_path, 'w') as f:
    json.dump(new_data, f, indent=2)
