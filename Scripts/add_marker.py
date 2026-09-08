"""Add a marker at the origin

A one point feature at latitude 0, longitude 0, named after the time it was
added at. Useful as a check that scripting reaches the document at all.
"""

uuid = app.add_feature("Marker at %g Ma" % app.time, rings=[[(0.0, 0.0)]],
                       geometry_kind="multipoint")
app.select(uuid)
print("added", uuid)
