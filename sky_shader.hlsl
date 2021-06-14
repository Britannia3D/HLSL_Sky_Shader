/**
 * Author: David McHale <mchale.d@yahoo.com>
 *
 * Adapted to hlsl from glsl
 *
 * Based on "A Practical Analytic Model for Daylight"
 * aka The Preetham Model, the de facto standard analytic skydome model
 *
*/

//Standard matrix buffer
cbuffer MatrixBuffer : register(b7)
{
	matrix worldMatrix;
	matrix viewMatrix;
	matrix projectionMatrix;
};

cbuffer SkyData : register(b1)
{
	float3 sunPosition;
		float padding1;
	float rayleigh;
		float3 padding2;	
	float turbidity;
		float3 padding3;
	float mieCoefficient;
		float3 padding4;
	float3 vWorldPosition;
		float padding5;
	float3 vSunDirection;
		float padding6;
	float vSunfade;
		float3 padding7;
	float3 vBetaR;
		float padding8;
	float3 vBetaM;
		float padding9;
	float vSunE;
		float3 padding10;
	float mieDirectionalG;
		float3 padding11;
	float exposure;
		float3 padding12;
};

//Vertex desc
struct VertexIn3
{
    float4 PosL : POSITION;
	float2 TexCoord : TEXCOORD0;
	float3 normal : NORMAL;
	float4 color : COLOR;
};

//Constants
const float sunAngularDiameterCos = 0.999956676946448443553574619906976478926848692873900859324;
const float whiteScale = 1.0748724675633854;

struct PixelIn3
{
	//Std:
	float4 position : SV_POSITION;
	float4 vWorldPosition : POSITION;
	float4 col : COLOR;

	float3 vBetaR : TEXCOORD0;
	float3 vBetaM : TEXCOORD1;
	float3 vSunDirection : POSITION2;
	float vSunE : TEXCOORD3;
	float vSunfade : TEXCOORD4;
	float mieDirectionalG : TEXCOORD5;
	float exposure : TEXCOORD6;
};

float sunIntensity(float zenithAngleCos)
{
	const float e = 2.71828182845904523536028747135266249775724709369995957;
	const float steepness = 1.5;
	const float cutoffAngle = 1.6110731556870734;
	zenithAngleCos = clamp( zenithAngleCos, -1.0, 1.0 );
	const float EE = 1000.0;
	return EE * max( 0.0, 1.0 - pow( e, -( ( cutoffAngle - acos( zenithAngleCos ) ) / steepness ) ) );
}

float3 totalMie( float T )
{
	const float3 MieConst = float3( 1.8399918514433978E14, 2.7798023919660528E14, 4.0790479543861094E14 );
	float c = ( 0.2 * T ) * 10E-18;
	return 0.434 * c * MieConst;
}

float rayleighPhase( float cosTheta )
{
	const float THREE_OVER_SIXTEENPI = 0.05968310365946075;
	return THREE_OVER_SIXTEENPI * ( 1.0 + pow( cosTheta, 2.0 ) );
}

float hgPhase( float cosTheta, float g )
{
	const float ONE_OVER_FOURPI = 0.07957747154594767;
	float g2 = pow( g, 2.0 );
	float inverse = 1.0 / pow( 1.0 - 2.0 * g * cosTheta + g2, 1.5 );
	return ONE_OVER_FOURPI * ( ( 1.0 - g2 ) * inverse );
}

const float A = 0.15;
const float B = 0.50;
const float C = 0.10;
const float D = 0.20;
const float E = 0.02;
const float F = 0.30;

float3 Uncharted2Tonemap( float3 x )
{
	return ( ( x * ( A * x + C * B ) + D * E ) / ( x * ( A * x + B ) + D * F ) ) - E / F;
}

//[Vertex shader]
PixelIn3 VS(VertexIn3 input)
{
	const float3 totalRayleigh = float3( 5.804542996261093E-6, 1.3562911419845635E-5, 3.0265902468824876E-5 );

	PixelIn3 output;
    output.position = mul(input.PosL, worldMatrix);
    output.position = mul(output.position, viewMatrix);
    output.position = mul(output.position, projectionMatrix);

	output.vWorldPosition = mul(input.PosL, worldMatrix);

	const float3 up = float3( 0.0, 1.0, 0.0 );
	float mieCoefficient_new = 0.005;
	float rayleigh_new = 3.0;
	float turbidity_new = 10;

	output.vSunDirection = normalize( sunPosition );
	output.vSunE = sunIntensity( dot( output.vSunDirection, up ) );
	output.vSunfade = 1.0 - clamp( 1.0 - exp( ( sunPosition.y / 450000.0 ) ), 0.0, 1.0 );

	float rayleighCoefficient = rayleigh - ( 1.0 * ( 1.0 - output.vSunfade ) );
	output.vBetaR = totalRayleigh * rayleighCoefficient;
	output.vBetaM = totalMie( turbidity ) *  mieCoefficient;

	output.mieDirectionalG = mieDirectionalG;
	output.exposure = exposure;

	output.col = input.color;

	return output;
}

//[Pixel shader]
float4 PS(PixelIn3 input) : SV_TARGET
{
	const float rayleighZenithLength = 8.4E3;
	const float mieZenithLength = 1.25E3;
	const float3 up = float3( 0.0, 1.0, 0.0 );
	const float pi = 3.141592653589793238462643383279502884197169;

	float3 vBetaR_new = input.vBetaR;//float3(0.5, 0.5, 0.5);

	float3 direction = normalize(input.vWorldPosition);

	float zenithAngle = acos( max( 0.0, dot( up, direction ) ) );
	float inverse = 1.0 / ( cos( zenithAngle ) + 0.15 * pow( 93.885 - ( ( zenithAngle * 180.0 ) / pi ), -1.253 ) );
	float sR = rayleighZenithLength * inverse;
	float sM = mieZenithLength * inverse;

	float3 Fex = exp( -( vBetaR_new * sR + input.vBetaM * sM ) );

	float cosTheta = dot( direction, input.vSunDirection );

	float rPhase = rayleighPhase( cosTheta * 0.5 + 0.5 );

	float3 betaRTheta = vBetaR_new * rPhase;
	float mieDirectionalG_new = 0.7;
										//0.8
	float mPhase = hgPhase( cosTheta, input.mieDirectionalG );// Was: float mPhase = hgPhase( cosTheta, mieDirectionalG_new );
	float3 betaMTheta = input.vBetaM * mPhase;

	float3 Lin = pow( input.vSunE * ( ( betaRTheta + betaMTheta ) / ( vBetaR_new + input.vBetaM ) ) * ( 1.0 - Fex ), float3( 1.5, 1.5, 1.5 ) );
	Lin *= lerp( float3( 1.0, 1.0, 1.0 ), pow( input.vSunE * ( ( betaRTheta + betaMTheta ) / ( vBetaR_new + input.vBetaM ) ) * Fex, float3( 0.5, 0.5, 0.5 ) ), clamp( pow( 1.0 - dot( up, input.vSunDirection ), 5.0 ), 0.0, 1.0 ) );
	
	float theta = acos( direction.y );
	float phi = atan2( direction.z, direction.x );
	float2 uv = float2( phi, theta ) / float2( 2.0 * pi, pi ) + float2( 0.5, 0.0 );
	float3 L0 = float3( 0.1, 0.1, 0.1 ) * Fex;

	//Sun disk
	const float sunAngularDiameterCos = 0.999956676946448443553574619906976478926848692873900859324;
	float sundisk = smoothstep( sunAngularDiameterCos, sunAngularDiameterCos + 0.00002, cosTheta );
	L0 += ( input.vSunE * 19000.0 * Fex ) * sundisk;

	float3 texColor = ( Lin + L0 ) * 0.04 + float3( 0.0, 0.0003, 0.00075 );
	float f = 1.0 / ( 1.2 + ( 1.2 * vSunfade ) );
	float3 retColor = pow( texColor * input.exposure, float3( f,f,f ) );

	return float4 (retColor, 1.0);
}