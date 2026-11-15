shader_type canvas_item;
render_mode unshaded;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 sky = vec2(uv.x * aspect, uv.y);
	vec3 color = vec3(0.0157, 0.0275, 0.0588);
	vec2 grid = sky * 105.0;
	vec2 cell = floor(grid);
	float seed = hash(cell);
	vec2 point = vec2(hash(cell + 3.0), hash(cell + 9.0));
	float star = (1.0 - smoothstep(0.005, 0.055, length(fract(grid) - point))) * step(0.975, seed);
	color += vec3(0.48, 0.71, 0.89) * star * (0.5 + 0.15 * sin(TIME * 0.4 + seed * 50.0));
	vec2 planet = vec2((uv.x - 0.48) * aspect, uv.y - 3.5);
	float radius = length(planet);
	float horizon = exp(-abs(radius - 2.68) * 90.0);
	float atmosphere = exp(-abs(radius - 2.68) * 16.0);
	color += vec3(0.035, 0.22, 0.39) * atmosphere * 0.5;
	color += vec3(0.22, 0.74, 0.97) * horizon * 0.7;
	float earth = 1.0 - smoothstep(2.66, 2.68, radius);
	float clouds = sin(sky.x * 17.0 + TIME * 0.014 + sin(uv.y * 31.0)) * 0.5 + 0.5;
	color = mix(color, vec3(0.008, 0.035, 0.075) + vec3(0.008, 0.04, 0.07) * clouds, earth * 0.85);
	COLOR = vec4(color, 1.0);
}
