// Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; adapted for TuneFreeNext. See THIRD_PARTY_NOTICES.md and scripts/vendor_folia_skins.mjs.
import {
  UboSystem,
  compileBufferSync,
  uboSyncFunctionsWGSL
} from "./chunk-I4JNEM5R.js";
import {
  ExtensionType
} from "./chunk-NJ7XHR5M.js";

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gpu/shader/utils/createUboElementsWGSL.mjs
var WGSL_ALIGN_SIZE_DATA = {
  i32: { align: 4, size: 4 },
  u32: { align: 4, size: 4 },
  f32: { align: 4, size: 4 },
  f16: { align: 2, size: 2 },
  "vec2<i32>": { align: 8, size: 8 },
  "vec2<u32>": { align: 8, size: 8 },
  "vec2<f32>": { align: 8, size: 8 },
  "vec2<f16>": { align: 4, size: 4 },
  "vec3<i32>": { align: 16, size: 12 },
  "vec3<u32>": { align: 16, size: 12 },
  "vec3<f32>": { align: 16, size: 12 },
  "vec3<f16>": { align: 8, size: 6 },
  "vec4<i32>": { align: 16, size: 16 },
  "vec4<u32>": { align: 16, size: 16 },
  "vec4<f32>": { align: 16, size: 16 },
  "vec4<f16>": { align: 8, size: 8 },
  "mat2x2<f32>": { align: 8, size: 16 },
  "mat2x2<f16>": { align: 4, size: 8 },
  "mat3x2<f32>": { align: 8, size: 24 },
  "mat3x2<f16>": { align: 4, size: 12 },
  "mat4x2<f32>": { align: 8, size: 32 },
  "mat4x2<f16>": { align: 4, size: 16 },
  "mat2x3<f32>": { align: 16, size: 32 },
  "mat2x3<f16>": { align: 8, size: 16 },
  "mat3x3<f32>": { align: 16, size: 48 },
  "mat3x3<f16>": { align: 8, size: 24 },
  "mat4x3<f32>": { align: 16, size: 64 },
  "mat4x3<f16>": { align: 8, size: 32 },
  "mat2x4<f32>": { align: 16, size: 32 },
  "mat2x4<f16>": { align: 8, size: 16 },
  "mat3x4<f32>": { align: 16, size: 48 },
  "mat3x4<f16>": { align: 8, size: 24 },
  "mat4x4<f32>": { align: 16, size: 64 },
  "mat4x4<f16>": { align: 8, size: 32 }
};
function createUboElementsWGSL(uniformData) {
  const uboElements = uniformData.map((data) => ({
    data,
    offset: 0,
    size: 0
  }));
  let offset = 0;
  for (let i = 0; i < uboElements.length; i++) {
    const uboElement = uboElements[i];
    let size = WGSL_ALIGN_SIZE_DATA[uboElement.data.type].size;
    const align = WGSL_ALIGN_SIZE_DATA[uboElement.data.type].align;
    if (!WGSL_ALIGN_SIZE_DATA[uboElement.data.type]) {
      throw new Error(`[Pixi.js] WebGPU UniformBuffer: Unknown type ${uboElement.data.type}`);
    }
    if (uboElement.data.size > 1) {
      size = Math.max(size, align) * uboElement.data.size;
    }
    offset = Math.ceil(offset / align) * align;
    uboElement.size = size;
    uboElement.offset = offset;
    offset += size;
  }
  offset = Math.ceil(offset / 16) * 16;
  return { uboElements, size: offset };
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gpu/shader/utils/generateArraySyncWGSL.mjs
function generateArraySyncWGSL(uboElement, offsetToAdd) {
  const { size, align } = WGSL_ALIGN_SIZE_DATA[uboElement.data.type];
  const remainder = (align - size) / 4;
  const data = uboElement.data.type.indexOf("i32") >= 0 ? "dataInt32" : "data";
  return `
         v = uv.${uboElement.data.name};
         ${offsetToAdd !== 0 ? `offset += ${offsetToAdd};` : ""}

         arrayOffset = offset;

         t = 0;

         for(var i=0; i < ${uboElement.data.size * (size / 4)}; i++)
         {
             for(var j = 0; j < ${size / 4}; j++)
             {
                 ${data}[arrayOffset++] = v[t++];
             }
             ${remainder !== 0 ? `arrayOffset += ${remainder};` : ""}
         }
     `;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gpu/shader/utils/createUboSyncFunctionWGSL.mjs
function createUboSyncFunctionWGSL(uboElements) {
  return compileBufferSync(
    uboElements,
    uboSyncFunctionsWGSL,
    generateArraySyncWGSL
  );
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gpu/GpuUboSystem.mjs
var GpuUboSystem = class extends UboSystem {
  constructor() {
    super({
      createUboElements: createUboElementsWGSL,
      generateUboSync: createUboSyncFunctionWGSL
    });
  }
};
GpuUboSystem.extension = {
  type: [ExtensionType.WebGPUSystem],
  name: "ubo"
};

export {
  WGSL_ALIGN_SIZE_DATA,
  createUboElementsWGSL,
  generateArraySyncWGSL,
  createUboSyncFunctionWGSL,
  GpuUboSystem
};
