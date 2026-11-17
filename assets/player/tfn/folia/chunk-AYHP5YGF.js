// Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; adapted for TuneFreeNext. See THIRD_PARTY_NOTICES.md and scripts/vendor_folia_skins.mjs.
import {
  STENCIL_MODES
} from "./chunk-Y6PH2CVJ.js";
import {
  getAttributeInfoFromFormat,
  warn
} from "./chunk-NJ7XHR5M.js";

// scripts/folia/node_modules/pixi.js/lib/rendering/high-shader/shader-bits/localUniformBit.mjs
var localUniformBit = {
  name: "local-uniform-bit",
  vertex: {
    header: (
      /* wgsl */
      `

            struct LocalUniforms {
                uTransformMatrix:mat3x3<f32>,
                uColor:vec4<f32>,
                uRound:f32,
            }

            @group(1) @binding(0) var<uniform> localUniforms : LocalUniforms;
        `
    ),
    main: (
      /* wgsl */
      `
            vColor *= localUniforms.uColor;
            modelMatrix *= localUniforms.uTransformMatrix;
        `
    ),
    end: (
      /* wgsl */
      `
            if(localUniforms.uRound == 1)
            {
                vPosition = vec4(roundPixels(vPosition.xy, globalUniforms.uResolution), vPosition.zw);
            }
        `
    )
  }
};
var localUniformBitGroup2 = {
  ...localUniformBit,
  vertex: {
    ...localUniformBit.vertex,
    // replace the group!
    header: localUniformBit.vertex.header.replace("group(1)", "group(2)")
  }
};
var localUniformBitGl = {
  name: "local-uniform-bit",
  vertex: {
    header: (
      /* glsl */
      `

            uniform mat3 uTransformMatrix;
            uniform vec4 uColor;
            uniform float uRound;
        `
    ),
    main: (
      /* glsl */
      `
            vColor *= uColor;
            modelMatrix = uTransformMatrix;
        `
    ),
    end: (
      /* glsl */
      `
            if(uRound == 1.)
            {
                gl_Position.xy = roundPixels(gl_Position.xy, uResolution);
            }
        `
    )
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/high-shader/shader-bits/textureBit.mjs
var textureBit = {
  name: "texture-bit",
  vertex: {
    header: (
      /* wgsl */
      `

        struct TextureUniforms {
            uTextureMatrix:mat3x3<f32>,
        }

        @group(2) @binding(2) var<uniform> textureUniforms : TextureUniforms;
        `
    ),
    main: (
      /* wgsl */
      `
            uv = (textureUniforms.uTextureMatrix * vec3(uv, 1.0)).xy;
        `
    )
  },
  fragment: {
    header: (
      /* wgsl */
      `
            @group(2) @binding(0) var uTexture: texture_2d<f32>;
            @group(2) @binding(1) var uSampler: sampler;


        `
    ),
    main: (
      /* wgsl */
      `
            outColor = textureSample(uTexture, uSampler, vUV);
        `
    )
  }
};
var textureBitGl = {
  name: "texture-bit",
  vertex: {
    header: (
      /* glsl */
      `
            uniform mat3 uTextureMatrix;
        `
    ),
    main: (
      /* glsl */
      `
            uv = (uTextureMatrix * vec3(uv, 1.0)).xy;
        `
    )
  },
  fragment: {
    header: (
      /* glsl */
      `
        uniform sampler2D uTexture;


        `
    ),
    main: (
      /* glsl */
      `
            outColor = texture(uTexture, vUV);
        `
    )
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/ensureAttributes.mjs
function ensureAttributes(geometry, extractedData) {
  for (const i in geometry.attributes) {
    const attribute = geometry.attributes[i];
    const attributeData = extractedData[i];
    if (attributeData) {
      attribute.format ?? (attribute.format = attributeData.format);
      attribute.offset ?? (attribute.offset = attributeData.offset);
      attribute.instance ?? (attribute.instance = attributeData.instance);
    } else {
      warn(`Attribute ${i} is not present in the shader, but is present in the geometry. Unable to infer attribute details.`);
    }
  }
  ensureStartAndStride(geometry);
}
function ensureStartAndStride(geometry) {
  const { buffers, attributes } = geometry;
  const tempStride = {};
  const tempStart = {};
  for (const j in buffers) {
    const buffer = buffers[j];
    tempStride[buffer.uid] = 0;
    tempStart[buffer.uid] = 0;
  }
  for (const j in attributes) {
    const attribute = attributes[j];
    tempStride[attribute.buffer.uid] += getAttributeInfoFromFormat(attribute.format).stride;
  }
  for (const j in attributes) {
    const attribute = attributes[j];
    attribute.stride ?? (attribute.stride = tempStride[attribute.buffer.uid]);
    attribute.start ?? (attribute.start = tempStart[attribute.buffer.uid]);
    tempStart[attribute.buffer.uid] += getAttributeInfoFromFormat(attribute.format).stride;
  }
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gpu/state/GpuStencilModesToPixi.mjs
var GpuStencilModesToPixi = [];
GpuStencilModesToPixi[STENCIL_MODES.NONE] = void 0;
GpuStencilModesToPixi[STENCIL_MODES.DISABLED] = {
  stencilWriteMask: 0,
  stencilReadMask: 0
};
GpuStencilModesToPixi[STENCIL_MODES.RENDERING_MASK_ADD] = {
  stencilFront: {
    compare: "equal",
    passOp: "increment-clamp"
  },
  stencilBack: {
    compare: "equal",
    passOp: "increment-clamp"
  }
};
GpuStencilModesToPixi[STENCIL_MODES.RENDERING_MASK_REMOVE] = {
  stencilFront: {
    compare: "equal",
    passOp: "decrement-clamp"
  },
  stencilBack: {
    compare: "equal",
    passOp: "decrement-clamp"
  }
};
GpuStencilModesToPixi[STENCIL_MODES.MASK_ACTIVE] = {
  stencilWriteMask: 0,
  stencilFront: {
    compare: "equal",
    passOp: "keep"
  },
  stencilBack: {
    compare: "equal",
    passOp: "keep"
  }
};
GpuStencilModesToPixi[STENCIL_MODES.INVERSE_MASK_ACTIVE] = {
  stencilWriteMask: 0,
  stencilFront: {
    compare: "not-equal",
    passOp: "keep"
  },
  stencilBack: {
    compare: "not-equal",
    passOp: "keep"
  }
};

export {
  localUniformBit,
  localUniformBitGroup2,
  localUniformBitGl,
  textureBit,
  textureBitGl,
  ensureAttributes,
  GpuStencilModesToPixi
};
