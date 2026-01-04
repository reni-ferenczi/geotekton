shader_type spatial;

uniform sampler2D earth_tex : source_color;
uniform vec4 grid_color = vec4(1.0, 1.0, 1.0, 0.3333);
uniform float grid_width = 0.0625;
uniform int lon_split = 24;
uniform int lat_split = 12;

void fragment() {
    // Fetch base Earth color
    vec4 earth = texture(earth_tex, UV);

    // Lat/Lon procedural
    float u = UV.x;
    float v = UV.y;

    // longitude lines
    float lon_step = 1.0 / float(lon_split);
	int lon_index = int(floor(u / lon_step));
    float lon_mod = abs(fract(u / lon_step));
	float lon_width = grid_width * ((lon_index & 1) == 0 ? 0.5 : 0.5);
    float lon_line = lon_mod < lon_width ? 1.0 : 0.0;
	
    // latitude lines
    float lat_step = 1.0 / float(lat_split);
	int lat_index = int(floor(v / lat_step));
    float lat_mod = abs(fract(v / lat_step));
	float lat_width = grid_width * ((lat_index & 1) == 0 ? 0.5 : 0.25);
    float lat_line = lat_mod < lat_width ? 1.0 : 0.0;

    // mix grid & earth
    vec4 grid = grid_color * max(lon_line, lat_line);

    ALBEDO = mix(earth.rgb, grid.rgb, grid.a * 0.8);
    ALPHA = 1.0;
}
