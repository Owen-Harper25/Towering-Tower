shader_type canvas_item;

uniform sampler2D mask : filter_nearest;

void fragment() {
    // 1. Get the current color of the ColorRect (the one being Tweened)
	vec4 current_rect_color = COLOR; 
    
    // 2. Check the mask (white = 1.0, black = 0.0)
	float mask_val = texture(mask, UV).r;
    
    // 3. Set the final color
    // We keep the RGB from the tween and modify only the Alpha
	COLOR = vec4(current_rect_color.rgb, current_rect_color.a * (1.0 - mask_val));
}