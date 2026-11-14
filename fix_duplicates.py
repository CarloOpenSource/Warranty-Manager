# Read the file
with open('lib/Screens/edit_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the position of the first "/// Parameter für Hintergrund-Speichern"
marker_pos = content.rfind("/// Parameter für Hintergrund-Speichern")
print(f"Marker position: {marker_pos}")

# Find the closing brace of _EditScreenState class before the duplicate methods
class_end_pos = content.rfind("}\n\n/// Parameter für Hintergrund-Speichern")
print(f"Class end position: {class_end_pos}")

if class_end_pos > 0:
    # Keep everything up to and including the closing brace of _EditScreenState
    new_content = content[:class_end_pos + 1] + "\n\n" + content[marker_pos:]
    with open('lib/Screens/edit_screen.dart', 'w', encoding='utf-8') as f:
        f.write(new_content)
    print("Fixed duplicate methods")
else:
    print("Could not find class end")
