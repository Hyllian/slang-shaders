#version 450

/*
   Interlacing
   
   Copyright (C) 2020 - 2025 guest(r)

   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; either version 2
   of the License, or (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
   
*/  


layout(push_constant) uniform Push
{
	vec4 OriginalSize;
	vec4 OutputSize;
	vec4 SourceSize;
	uint FrameCount;
	float GAMMA_INPUT;
	float inter;
	float interm;
	float inters;
	float iscan;
	float intres;
	float gamma_out;
} params;


layout(std140, set = 0, binding = 0) uniform UBO
{
	mat4 MVP;
} global;

#pragma parameter bogus_gamma "[ GAMMA OPTIONS ]: " 0.0 0.0 0.0 1.0

#pragma parameter GAMMA_INPUT "          Gamma Input" 2.4 1.0 5.0 0.05
#define GAMMA_INPUT params.GAMMA_INPUT

#pragma parameter gamma_out "          Gamma out" 2.4 1.0 5.0 0.05
#define gamma_out    params.gamma_out     // output gamma

#pragma parameter bogus_interlacing "[ INTERLACING OPTIONS ]: " 0.0 0.0 0.0 1.0

#pragma parameter inter "          Interlace Trigger Resolution :" 400.0 0.0 800.0 25.0
#define inter         params.inter     // interlace resolution

#pragma parameter interm "          Interlace Mode: OFF, Normal 1-3, Interpolation 4-5" 1.0 0.0 5.0 1.0
#define interm         params.interm     // interlace mode 

#pragma parameter intres "          Internal Resolution Y: 0.5...y-dowsample" 0.0 0.0 3.0 0.5 // Joint parameter with main pass, values must match
#define intres         params.intres     // interlace resolution

#pragma parameter inters "          Interlacing Effect Smoothness" 0.0 0.0 0.5 0.05 // // Joint parameter with main pass, values must match
#define inters  params.inters     // interlacing effect smoothing

#pragma parameter iscan "          Interlacing Scanline Effect ('Laced brightness)" 0.20 0.0 1.0 0.05
#define iscan  params.iscan     // interlacing effect scanlining


#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
   gl_Position = global.MVP * Position;
   vTexCoord = TexCoord * 1.00001;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

#define COMPAT_TEXTURE(c,d) texture(c,d)
#define SourceSize  params.SourceSize


vec3 plant (vec3 tar, float r)
{
	float t = max(max(tar.r,tar.g),tar.b) + 0.00001;
	return tar * r / t;
}


void main()
{
	vec3  c1 = COMPAT_TEXTURE(Source, vTexCoord).rgb;
	vec3  c2 = COMPAT_TEXTURE(Source, vTexCoord + vec2(0.0, 1.0/params.OriginalSize.y)).rgb;	
	vec3  c  = c1;

	float intera = 1.0;
	float gamma_in = GAMMA_INPUT;

	float m1 = max(max(c1.r,c1.g),c1.b);
	float m2 = max(max(c2.r,c2.g),c2.b);
	vec3 df = abs(c1-c2);
		
	float d = max(max(df.r,df.g),df.b);
	if (interm == 2.0) d = mix(0.1*d,10.0*d, step(m1/(m2+0.0001),m2/(m1+0.0001)));

	float r = m1;
		
	float yres_div = 1.0; if (intres > 1.25) yres_div = intres;
		
	if (inter <= params.OriginalSize.y/yres_div && interm > 0.5 && intres != 0.5) 
	{
		intera = 0.25;
		float line_no  = floor(mod(params.OriginalSize.y*vTexCoord.y, 2.0));
		float frame_no = floor(mod(float(params.FrameCount),2.0));
		float ii = abs(line_no-frame_no);
		
		if (interm < 3.5)
		{
			r = max(m1*ii, (1.0-iscan)*min(m1,m2));
			c = plant( mix(mix(c1,c2, min(mix(m1, 1.0-m2, min(m1,1.0-m1))/(d+0.00001),1.0)), c1, ii), r);
			if (interm == 3.0) c = (1.0-0.5*iscan)*mix(c2, c1, ii);
		}
		if (interm == 4.0) { c = c * (1.0-0.5*iscan); }		
		if (interm == 5.0) { c = mix(c2, c1, 0.5) * (1.0-0.5*iscan); }
	}
	c = pow(c, vec3(gamma_in));
	
	if (vTexCoord.x > 0.5) gamma_in = intera; else gamma_in = 1.0/gamma_in;
	
	FragColor = vec4(c, gamma_in);
}