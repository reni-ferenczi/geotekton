shader_type spatial;
render_mode unshaded, blend_add;

// The stars behind the planet, worked out per fragment instead of read from an
// image. The quad's UV is cut into cells, and each cell's integer coordinates
// and the seed decide whether it holds a star and what that star looks like.
// Distances are in texels of the 8192 by 4096 image this replaced, so the
// sizes and density stay what that image had.

const vec2 CELLS = vec2(1024.0, 512.0);
const float CELL_TEXELS = 8.0;

// About half the cells hold a star, which is close to the image's 250 000.
const float STAR_CHANCE = 0.5;

// Tints taken away from a star's grey, in 0-255 steps: white, a little blue
// and a little yellow.
const vec3 TINTS[3] = { vec3(0.0), vec3(20.0, 10.0, 0.0), vec3(0.0, 0.0, 20.0) };

// Scales the light so a patch of sky is as bright as it was with the image,
// whose compression and mipmaps took some of it away. Measured on the corner
// patch of Tests/Rendered/test_scene.gd.
const float GAIN = 0.45;

uniform float seed = 7.0;

// A number in [0, 1) that depends only on the cell, the seed and which of the
// star's properties it is for.
float hash(ivec2 cell, uint property) {
	uint h = uint(cell.x) * 0x8da6b343u ^ uint(cell.y) * 0xd8163841u
		^ (uint(seed) * 16u + property) * 0xcb1ab31fu;
	h ^= h >> 16u;
	h *= 0x7feb352du;
	h ^= h >> 15u;
	h *= 0x846ca68bu;
	h ^= h >> 16u;
	return float(h >> 8u) / 16777216.0;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	vec2 texel = UV * CELLS * CELL_TEXELS;
	// How many texels one screen pixel covers.
	float footprint = max(fwidth(texel.x), fwidth(texel.y));
	ivec2 home = ivec2(floor(texel / CELL_TEXELS));
	vec3 light = vec3(0.0);

	// A star can reach over its cell's border, so the neighbours are asked too.
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 cell = home + ivec2(dx, dy);
			if (hash(cell, 0u) >= STAR_CHANCE) {
				continue;
			}
			vec2 centre = (vec2(cell) + vec2(hash(cell, 1u), hash(cell, 2u))) * CELL_TEXELS;
			float pick = hash(cell, 3u);
			float size = pick < 0.85 ? 1.0 : (pick < 0.97 ? 2.0 : 3.0);
			float brightness = floor(hash(cell, 4u) * 85.0 * size) + 1.0;
			vec3 colour = max(vec3(brightness) - TINTS[int(hash(cell, 5u) * 3.0)], 0.0) / 255.0;

			// The image drew a star as a disc size - 1 pixels round a centre
			// pixel, which is half a texel more than that. A star smaller than
			// a pixel is spread over one and dimmed to keep its light, so it
			// neither vanishes nor flickers as the view moves.
			float own = size - 0.5;
			float radius = max(own, 0.5 * footprint);
			float edge = 0.5 * footprint;
			float cover = 1.0 - smoothstep(radius - edge, radius + edge, distance(texel, centre));
			light += srgb_to_linear(colour) * cover * (own * own) / (radius * radius);
		}
	}
	ALBEDO = light * GAIN;
}
