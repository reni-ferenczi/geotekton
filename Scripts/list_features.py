"""List the features of the open document

Prints one line per feature: its title, the kind of geometry it has, how many
vertices that comes to and how many keyframes it moves through.
"""

for feature in app.features:
    vertices = sum(len(ring) for ring in feature.rings)
    print("%-24s %-10s %3d vertices, %d keyframes" % (
        feature.title, feature.geometry_kind, vertices, len(feature.keyframes)))
