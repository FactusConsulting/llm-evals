import csv
import json

def convert(input_file, output_file):
    data = []
    with open(input_file, mode='r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            new_row = {}
            for key, value in row.items():
                # Try converting to int, then float, otherwise keep as string
                try:
                    if '.' in value:
                        new_row[key] = float(value)
                    else:
                        new_row[key] = int(value)
                except ValueError:
                    new_row[key] = value
            data.append(new_row)
    
    with open(output_file, mode='w', encoding='utf-8') as f:
        json.dump(data, f, indent=4)

if __name__ == "__main__":
    convert('/tmp/ageval/data.csv', '/tmp/ageval/data.json')
