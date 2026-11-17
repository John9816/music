// Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; adapted for TuneFreeNext. See THIRD_PARTY_NOTICES.md and scripts/vendor_folia_skins.mjs.
import {
  ViewableBuffer
} from "./chunk-LXMKFHNO.js";
import {
  GlProgram,
  GpuProgram,
  Shader,
  getTestContext
} from "./chunk-2SNS7NNO.js";
import {
  Buffer,
  BufferUsage,
  ExtensionType,
  Geometry,
  GlobalResourceRegistry,
  UniformGroup,
  deprecation,
  uid,
  warn
} from "./chunk-NJ7XHR5M.js";

// scripts/folia/node_modules/pixi.js/lib/rendering/high-shader/compiler/utils/addBits.mjs
function addBits(srcParts, parts, name) {
  if (srcParts) {
    for (const i in srcParts) {
      const id = i.toLocaleLowerCase();
      const part = parts[id];
      if (part) {
        let sanitisedPart = srcParts[i];
        if (i === "header") {
          sanitisedPart = sanitisedPart.replace(/@in\s+[^;]+;\s*/g, "").replace(/@out\s+[^;]+;\s*/g, "");
        }
        if (name) {
          part.push(`//----${name}----//`);
        }
        part.push(sanitisedPart);
      } else {
        warn(`${i} placement hook does not exist in shader`);
      }
    }
  }
}

// scripts/folia/node_modules/pixi.js/lib/rendering/high-shader/compiler/utils/compileHooks.mjs
var findHooksRx = /\{\{(.*?)\}\}/g;
function compileHooks(programSrc) {
  const parts = {};
  const partMatches = programSrc.match(findHooksRx)?.map((hook) => hook.replace(/[{()}]/g, "")) ?? [];
  partMatches.forEach((hook) => {
    parts[hook] = [];
  });
  return parts;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/high-shader/compiler/utils/compileInputs.mjs
function extractInputs(fragmentSource, out) {
  let match;
  const regex = /@in\s+([^;]+);/g;
  while ((match = regex.exec(fragmentSource)) !== null) {
    out.push(match[1]);
  }
}
function compileInputs(fragments, template, sort = false) {
  const results = [];
  extractInputs(template, results);
  fragments.forEach((fragment) => {
    if (fragment.header) {
      extractInputs(fragment.header, results);
    }
  });
  const mainInput = results;
  if (sort) {
    mainInput.sort();
  }
  const finalString = mainInput.map((inValue, i) => `       @location(${i}) ${inValue},`).join("\n");
  let cleanedString = template.replace(/@in\s+[^;]+;\s*/g, "");
  cleanedString = cleanedString.replace("{{in}}", `
${finalString}
`);
  return cleanedString;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/high-shader/compiler/utils/compileOutputs.mjs
function extractOutputs(fragmentSource, out) {
  let match;
  const regex = /@out\s+([^;]+);/g;
  while ((match = regex.exec(fragmentSource)) !== null) {
    out.push(match[1]);
  }
}
function extractVariableName(value) {
  const regex = /\b(\w+)\s*:/g;
  const match = regex.exec(value);
  return match ? match[1] : "";
}
function stripVariable(value) {
  const regex = /@.*?\s+/g;
  return value.replace(regex, "");
}
function compileOutputs(fragments, template) {
  const results = [];
  extractOutputs(template, results);
  fragments.forEach((fragment) => {
    if (fragment.header) {
      extractOutputs(fragment.header, results);
    }
  });
  let index = 0;
  const mainStruct = results.sort().map((inValue) => {
    if (inValue.indexOf("builtin") > -1) {
      return inValue;
    }
    return `@location(${index++}) ${inValue}`;
  }).join(",\n");
  const mainStart = results.sort().map((inValue) => `       var ${stripVariable(inValue)};`).join("\n");
  const mainEnd = `return VSOutput(
            ${results.sort().map((inValue) => ` ${extractVariableName(inValue)}`).join(",\n")});`;
  let compiledCode = template.replace(/@out\s+[^;]+;\s*/g, "");
  compiledCode = compiledCode.replace("{{struct}}", `
${mainStruct}
`);
  compiledCode = compiledCode.replace("{{start}}", `
${mainStart}
`);
  compiledCode = compiledCode.replace("{{return}}", `
${mainEnd}
`);
  return compiledCode;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/high-shader/compiler/utils/injectBits.mjs
function injectBits(templateSrc, fragmentParts) {
  let out = templateSrc;
  for (const i in fragmentParts) {
    const parts = fragmentParts[i];
    const toInject = parts.join("\n");
    if (toInject.length) {
      out = out.replace(`{{${i}}}`, `//-----${i} START-----//
${parts.join("\n")}
//----${i} FINISH----//`);
    } else {
      out = out.replace(`{{${i}}}`, "");
    }
  }
  return out;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/high-shader/compiler/compileHighShader.mjs
var cacheMap = /* @__PURE__ */ Object.create(null);
var bitCacheMap = /* @__PURE__ */ new Map();
var CACHE_UID = 0;
function compileHighShader({
  template,
  bits
}) {
  const cacheId = generateCacheId(template, bits);
  if (cacheMap[cacheId]) return cacheMap[cacheId];
  const { vertex, fragment } = compileInputsAndOutputs(template, bits);
  cacheMap[cacheId] = compileBits(vertex, fragment, bits);
  return cacheMap[cacheId];
}
function compileHighShaderGl({
  template,
  bits
}) {
  const cacheId = generateCacheId(template, bits);
  if (cacheMap[cacheId]) return cacheMap[cacheId];
  cacheMap[cacheId] = compileBits(template.vertex, template.fragment, bits);
  return cacheMap[cacheId];
}
function compileInputsAndOutputs(template, bits) {
  const vertexFragments = bits.map((shaderBit) => shaderBit.vertex).filter((v) => !!v);
  const fragmentFragments = bits.map((shaderBit) => shaderBit.fragment).filter((v) => !!v);
  let compiledVertex = compileInputs(vertexFragments, template.vertex, true);
  compiledVertex = compileOutputs(vertexFragments, compiledVertex);
  const compiledFragment = compileInputs(fragmentFragments, template.fragment, true);
  return {
    vertex: compiledVertex,
    fragment: compiledFragment
  };
}
function generateCacheId(template, bits) {
  return bits.map((highFragment) => {
    if (!bitCacheMap.has(highFragment)) {
      bitCacheMap.set(highFragment, CACHE_UID++);
    }
    return bitCacheMap.get(highFragment);
  }).sort((a, b) => a - b).join("-") + template.vertex + template.fragment;
}
function compileBits(vertex, fragment, bits) {
  const vertexParts = compileHooks(vertex);
  const fragmentParts = compileHooks(fragment);
  bits.forEach((shaderBit) => {
    addBits(shaderBit.vertex, vertexParts, shaderBit.name);
    addBits(shaderBit.fragment, fragmentParts, shaderBit.name);
  });
  return {
    vertex: injectBits(vertex, vertexParts),
    fragment: injectBits(fragment, fragmentParts)
  };
}

// scripts/folia/node_modules/pixi.js/lib/rendering/high-shader/defaultProgramTemplate.mjs
var vertexGPUTemplate = (
  /* wgsl */
  `
    @in aPosition: vec2<f32>;
    @in aUV: vec2<f32>;

    @out @builtin(position) vPosition: vec4<f32>;
    @out vUV : vec2<f32>;
    @out vColor : vec4<f32>;

    {{header}}

    struct VSOutput {
        {{struct}}
    };

    @vertex
    fn main( {{in}} ) -> VSOutput {

        var worldTransformMatrix = globalUniforms.uWorldTransformMatrix;
        var modelMatrix = mat3x3<f32>(
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 1.0
          );
        var position = aPosition;
        var uv = aUV;

        {{start}}

        vColor = vec4<f32>(1., 1., 1., 1.);

        {{main}}

        vUV = uv;

        var modelViewProjectionMatrix = globalUniforms.uProjectionMatrix * worldTransformMatrix * modelMatrix;

        vPosition =  vec4<f32>((modelViewProjectionMatrix *  vec3<f32>(position, 1.0)).xy, 0.0, 1.0);

        vColor *= globalUniforms.uWorldColorAlpha;

        {{end}}

        {{return}}
    };
`
);
var fragmentGPUTemplate = (
  /* wgsl */
  `
    @in vUV : vec2<f32>;
    @in vColor : vec4<f32>;

    {{header}}

    @fragment
    fn main(
        {{in}}
      ) -> @location(0) vec4<f32> {

        {{start}}

        var outColor:vec4<f32>;

        {{main}}

        var finalColor:vec4<f32> = outColor * vColor;

        {{end}}

        return finalColor;
      };
`
);
var vertexGlTemplate = (
  /* glsl */
  `
    in vec2 aPosition;
    in vec2 aUV;

    out vec4 vColor;
    out vec2 vUV;

    {{header}}

    void main(void){

        mat3 worldTransformMatrix = uWorldTransformMatrix;
        mat3 modelMatrix = mat3(
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 1.0
          );
        vec2 position = aPosition;
        vec2 uv = aUV;

        {{start}}

        vColor = vec4(1.);

        {{main}}

        vUV = uv;

        mat3 modelViewProjectionMatrix = uProjectionMatrix * worldTransformMatrix * modelMatrix;

        gl_Position = vec4((modelViewProjectionMatrix * vec3(position, 1.0)).xy, 0.0, 1.0);

        vColor *= uWorldColorAlpha;

        {{end}}
    }
`
);
var fragmentGlTemplate = (
  /* glsl */
  `

    in vec4 vColor;
    in vec2 vUV;

    out vec4 finalColor;

    {{header}}

    void main(void) {

        {{start}}

        vec4 outColor;

        {{main}}

        finalColor = outColor * vColor;

        {{end}}
    }
`
);

// scripts/folia/node_modules/pixi.js/lib/rendering/high-shader/shader-bits/globalUniformsBit.mjs
var globalUniformsBit = {
  name: "global-uniforms-bit",
  vertex: {
    header: (
      /* wgsl */
      `
        struct GlobalUniforms {
            uProjectionMatrix:mat3x3<f32>,
            uWorldTransformMatrix:mat3x3<f32>,
            uWorldColorAlpha: vec4<f32>,
            uResolution: vec2<f32>,
        }

        @group(0) @binding(0) var<uniform> globalUniforms : GlobalUniforms;
        `
    )
  }
};
var globalUniformsUBOBitGl = {
  name: "global-uniforms-ubo-bit",
  vertex: {
    header: (
      /* glsl */
      `
          uniform globalUniforms {
            mat3 uProjectionMatrix;
            mat3 uWorldTransformMatrix;
            vec4 uWorldColorAlpha;
            vec2 uResolution;
          };
        `
    )
  }
};
var globalUniformsBitGl = {
  name: "global-uniforms-bit",
  vertex: {
    header: (
      /* glsl */
      `
          uniform mat3 uProjectionMatrix;
          uniform mat3 uWorldTransformMatrix;
          uniform vec4 uWorldColorAlpha;
          uniform vec2 uResolution;
        `
    )
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/high-shader/compileHighShaderToProgram.mjs
function compileHighShaderGpuProgram({ bits, name }) {
  const source = compileHighShader({
    template: {
      fragment: fragmentGPUTemplate,
      vertex: vertexGPUTemplate
    },
    bits: [
      globalUniformsBit,
      ...bits
    ]
  });
  return GpuProgram.from({
    name,
    vertex: {
      source: source.vertex,
      entryPoint: "main"
    },
    fragment: {
      source: source.fragment,
      entryPoint: "main"
    }
  });
}
function compileHighShaderGlProgram({ bits, name }) {
  return new GlProgram({
    name,
    ...compileHighShaderGl({
      template: {
        vertex: vertexGlTemplate,
        fragment: fragmentGlTemplate
      },
      bits: [
        globalUniformsBitGl,
        ...bits
      ]
    })
  });
}

// scripts/folia/node_modules/pixi.js/lib/rendering/high-shader/shader-bits/colorBit.mjs
var colorBit = {
  name: "color-bit",
  vertex: {
    header: (
      /* wgsl */
      `
            @in aColor: vec4<f32>;
        `
    ),
    main: (
      /* wgsl */
      `
            vColor *= vec4<f32>(aColor.rgb * aColor.a, aColor.a);
        `
    )
  }
};
var colorBitGl = {
  name: "color-bit",
  vertex: {
    header: (
      /* glsl */
      `
            in vec4 aColor;
        `
    ),
    main: (
      /* glsl */
      `
            vColor *= vec4(aColor.rgb * aColor.a, aColor.a);
        `
    )
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/high-shader/shader-bits/generateTextureBatchBit.mjs
var textureBatchBitGpuCache = {};
function generateBindingSrc(maxTextures) {
  const src = [];
  if (maxTextures === 1) {
    src.push("@group(1) @binding(0) var textureSource1: texture_2d<f32>;");
    src.push("@group(1) @binding(1) var textureSampler1: sampler;");
  } else {
    let bindingIndex = 0;
    for (let i = 0; i < maxTextures; i++) {
      src.push(`@group(1) @binding(${bindingIndex++}) var textureSource${i + 1}: texture_2d<f32>;`);
      src.push(`@group(1) @binding(${bindingIndex++}) var textureSampler${i + 1}: sampler;`);
    }
  }
  return src.join("\n");
}
function generateSampleSrc(maxTextures) {
  const src = [];
  if (maxTextures === 1) {
    src.push("outColor = textureSampleGrad(textureSource1, textureSampler1, vUV, uvDx, uvDy);");
  } else {
    src.push("switch vTextureId {");
    for (let i = 0; i < maxTextures; i++) {
      if (i === maxTextures - 1) {
        src.push(`  default:{`);
      } else {
        src.push(`  case ${i}:{`);
      }
      src.push(`      outColor = textureSampleGrad(textureSource${i + 1}, textureSampler${i + 1}, vUV, uvDx, uvDy);`);
      src.push(`      break;}`);
    }
    src.push(`}`);
  }
  return src.join("\n");
}
function generateTextureBatchBit(maxTextures) {
  if (!textureBatchBitGpuCache[maxTextures]) {
    textureBatchBitGpuCache[maxTextures] = {
      name: "texture-batch-bit",
      vertex: {
        header: `
                @in aTextureIdAndRound: vec2<u32>;
                @out @interpolate(flat) vTextureId : u32;
            `,
        main: `
                vTextureId = aTextureIdAndRound.y;
            `,
        end: `
                if(aTextureIdAndRound.x == 1)
                {
                    vPosition = vec4<f32>(roundPixels(vPosition.xy, globalUniforms.uResolution), vPosition.zw);
                }
            `
      },
      fragment: {
        header: `
                @in @interpolate(flat) vTextureId: u32;

                ${generateBindingSrc(maxTextures)}
            `,
        main: `
                var uvDx = dpdx(vUV);
                var uvDy = dpdy(vUV);

                ${generateSampleSrc(maxTextures)}
            `
      }
    };
  }
  return textureBatchBitGpuCache[maxTextures];
}
var textureBatchBitGlCache = {};
function generateSampleGlSrc(maxTextures) {
  const src = [];
  for (let i = 0; i < maxTextures; i++) {
    if (i > 0) {
      src.push("else");
    }
    if (i < maxTextures - 1) {
      src.push(`if(vTextureId < ${i}.5)`);
    }
    src.push("{");
    src.push(`	outColor = texture(uTextures[${i}], vUV);`);
    src.push("}");
  }
  return src.join("\n");
}
function generateTextureBatchBitGl(maxTextures) {
  if (!textureBatchBitGlCache[maxTextures]) {
    textureBatchBitGlCache[maxTextures] = {
      name: "texture-batch-bit",
      vertex: {
        header: `
                in vec2 aTextureIdAndRound;
                out float vTextureId;

            `,
        main: `
                vTextureId = aTextureIdAndRound.y;
            `,
        end: `
                if(aTextureIdAndRound.x == 1.)
                {
                    gl_Position.xy = roundPixels(gl_Position.xy, uResolution);
                }
            `
      },
      fragment: {
        header: `
                in float vTextureId;

                uniform sampler2D uTextures[${maxTextures}];

            `,
        main: `

                ${generateSampleGlSrc(maxTextures)}
            `
      }
    };
  }
  return textureBatchBitGlCache[maxTextures];
}

// scripts/folia/node_modules/pixi.js/lib/rendering/high-shader/shader-bits/roundPixelsBit.mjs
var roundPixelsBit = {
  name: "round-pixels-bit",
  vertex: {
    header: (
      /* wgsl */
      `
            fn roundPixels(position: vec2<f32>, targetSize: vec2<f32>) -> vec2<f32>
            {
                return (floor(((position * 0.5 + 0.5) * targetSize) + 0.5) / targetSize) * 2.0 - 1.0;
            }
        `
    )
  }
};
var roundPixelsBitGl = {
  name: "round-pixels-bit",
  vertex: {
    header: (
      /* glsl */
      `
            vec2 roundPixels(vec2 position, vec2 targetSize)
            {
                return (floor(((position * 0.5 + 0.5) * targetSize) + 0.5) / targetSize) * 2.0 - 1.0;
            }
        `
    )
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/shared/buffer/utils/fastCopy.mjs
function fastCopy(sourceBuffer, destinationBuffer, sourceOffset, byteLength) {
  sourceOffset ?? (sourceOffset = 0);
  byteLength ?? (byteLength = Math.min(sourceBuffer.byteLength - sourceOffset, destinationBuffer.byteLength));
  if (!(sourceOffset & 7) && !(byteLength & 7)) {
    const len = byteLength / 8;
    new Float64Array(destinationBuffer, 0, len).set(new Float64Array(sourceBuffer, sourceOffset, len));
  } else if (!(sourceOffset & 3) && !(byteLength & 3)) {
    const len = byteLength / 4;
    new Float32Array(destinationBuffer, 0, len).set(new Float32Array(sourceBuffer, sourceOffset, len));
  } else {
    new Uint8Array(destinationBuffer).set(new Uint8Array(sourceBuffer, sourceOffset, byteLength));
  }
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/shared/state/const.mjs
var BLEND_TO_NPM = {
  normal: "normal-npm",
  add: "add-npm",
  screen: "screen-npm"
};
var STENCIL_MODES = /* @__PURE__ */ ((STENCIL_MODES2) => {
  STENCIL_MODES2[STENCIL_MODES2["DISABLED"] = 0] = "DISABLED";
  STENCIL_MODES2[STENCIL_MODES2["RENDERING_MASK_ADD"] = 1] = "RENDERING_MASK_ADD";
  STENCIL_MODES2[STENCIL_MODES2["MASK_ACTIVE"] = 2] = "MASK_ACTIVE";
  STENCIL_MODES2[STENCIL_MODES2["INVERSE_MASK_ACTIVE"] = 3] = "INVERSE_MASK_ACTIVE";
  STENCIL_MODES2[STENCIL_MODES2["RENDERING_MASK_REMOVE"] = 4] = "RENDERING_MASK_REMOVE";
  STENCIL_MODES2[STENCIL_MODES2["NONE"] = 5] = "NONE";
  return STENCIL_MODES2;
})(STENCIL_MODES || {});

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/shared/state/getAdjustedBlendModeBlend.mjs
function getAdjustedBlendModeBlend(blendMode, textureSource) {
  if (textureSource.alphaMode === "no-premultiply-alpha") {
    return BLEND_TO_NPM[blendMode] || blendMode;
  }
  return blendMode;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/batcher/gl/utils/checkMaxIfStatementsInShader.mjs
var fragTemplate = [
  "precision mediump float;",
  "void main(void){",
  "float test = 0.1;",
  "%forloop%",
  "gl_FragColor = vec4(0.0);",
  "}"
].join("\n");
function generateIfTestSrc(maxIfs) {
  let src = "";
  for (let i = 0; i < maxIfs; ++i) {
    if (i > 0) {
      src += "\nelse ";
    }
    if (i < maxIfs - 1) {
      src += `if(test == ${i}.0){}`;
    }
  }
  return src;
}
function checkMaxIfStatementsInShader(maxIfs, gl) {
  if (maxIfs === 0) {
    throw new Error("Invalid value of `0` passed to `checkMaxIfStatementsInShader`");
  }
  const shader = gl.createShader(gl.FRAGMENT_SHADER);
  try {
    while (true) {
      const fragmentSrc = fragTemplate.replace(/%forloop%/gi, generateIfTestSrc(maxIfs));
      gl.shaderSource(shader, fragmentSrc);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        maxIfs = maxIfs / 2 | 0;
      } else {
        break;
      }
    }
  } finally {
    gl.deleteShader(shader);
  }
  return maxIfs;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/batcher/gl/utils/maxRecommendedTextures.mjs
var maxTexturesPerBatchCache = null;
function getMaxTexturesPerBatch() {
  if (maxTexturesPerBatchCache) return maxTexturesPerBatchCache;
  const gl = getTestContext();
  maxTexturesPerBatchCache = gl.getParameter(gl.MAX_TEXTURE_IMAGE_UNITS);
  maxTexturesPerBatchCache = checkMaxIfStatementsInShader(
    maxTexturesPerBatchCache,
    gl
  );
  gl.getExtension("WEBGL_lose_context")?.loseContext();
  return maxTexturesPerBatchCache;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/batcher/shared/BatchTextureArray.mjs
var BatchTextureArray = class {
  constructor() {
    this.ids = /* @__PURE__ */ Object.create(null);
    this.textures = [];
    this.count = 0;
  }
  /** Clear the textures and their locations. */
  clear() {
    for (let i = 0; i < this.count; i++) {
      const t = this.textures[i];
      this.textures[i] = null;
      this.ids[t.uid] = null;
    }
    this.count = 0;
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/batcher/shared/Batcher.mjs
var Batch = class {
  constructor() {
    this.renderPipeId = "batch";
    this.action = "startBatch";
    this.start = 0;
    this.size = 0;
    this.textures = new BatchTextureArray();
    this.blendMode = "normal";
    this.topology = "triangle-strip";
    this.canBundle = true;
  }
  destroy() {
    this.textures = null;
    this.gpuBindGroup = null;
    this.bindGroup = null;
    this.batcher = null;
    this.elements = null;
  }
};
var batchPool = [];
var batchPoolIndex = 0;
GlobalResourceRegistry.register({
  clear: () => {
    if (batchPool.length > 0) {
      for (const item of batchPool) {
        if (item) item.destroy();
      }
    }
    batchPool.length = 0;
    batchPoolIndex = 0;
  }
});
function getBatchFromPool() {
  return batchPoolIndex > 0 ? batchPool[--batchPoolIndex] : new Batch();
}
function returnBatchToPool(batch) {
  batch.elements = null;
  batchPool[batchPoolIndex++] = batch;
}
var BATCH_TICK = 0;
var _Batcher = class _Batcher2 {
  constructor(options) {
    this.uid = uid("batcher");
    this.dirty = true;
    this.batchIndex = 0;
    this.batches = [];
    this._elements = [];
    options = { ..._Batcher2.defaultOptions, ...options };
    if (!options.maxTextures) {
      deprecation("v8.8.0", "maxTextures is a required option for Batcher now, please pass it in the options");
      options.maxTextures = getMaxTexturesPerBatch();
    }
    const { maxTextures, attributesInitialSize, indicesInitialSize } = options;
    this.attributeBuffer = new ViewableBuffer(attributesInitialSize * 4);
    this.indexBuffer = new Uint16Array(indicesInitialSize);
    this.maxTextures = maxTextures;
  }
  begin() {
    this.elementSize = 0;
    this.elementStart = 0;
    this.indexSize = 0;
    this.attributeSize = 0;
    for (let i = 0; i < this.batchIndex; i++) {
      returnBatchToPool(this.batches[i]);
    }
    this.batchIndex = 0;
    this._batchIndexStart = 0;
    this._batchIndexSize = 0;
    this.dirty = true;
  }
  add(batchableObject) {
    this._elements[this.elementSize++] = batchableObject;
    batchableObject._indexStart = this.indexSize;
    batchableObject._attributeStart = this.attributeSize;
    batchableObject._batcher = this;
    this.indexSize += batchableObject.indexSize;
    this.attributeSize += batchableObject.attributeSize * this.vertexSize;
  }
  checkAndUpdateTexture(batchableObject, texture) {
    const textureId = batchableObject._batch.textures.ids[texture._source.uid];
    if (!textureId && textureId !== 0) return false;
    batchableObject._textureId = textureId;
    batchableObject.texture = texture;
    return true;
  }
  updateElement(batchableObject) {
    this.dirty = true;
    const attributeBuffer = this.attributeBuffer;
    if (batchableObject.packAsQuad) {
      this.packQuadAttributes(
        batchableObject,
        attributeBuffer.float32View,
        attributeBuffer.uint32View,
        batchableObject._attributeStart,
        batchableObject._textureId
      );
    } else {
      this.packAttributes(
        batchableObject,
        attributeBuffer.float32View,
        attributeBuffer.uint32View,
        batchableObject._attributeStart,
        batchableObject._textureId
      );
    }
  }
  /**
   * breaks the batcher. This happens when a batch gets too big,
   * or we need to switch to a different type of rendering (a filter for example)
   * @param instructionSet
   */
  break(instructionSet) {
    const elements = this._elements;
    if (!elements[this.elementStart]) return;
    let batch = getBatchFromPool();
    let textureBatch = batch.textures;
    textureBatch.clear();
    const firstElement = elements[this.elementStart];
    let blendMode = getAdjustedBlendModeBlend(firstElement.blendMode, firstElement.texture._source);
    let topology = firstElement.topology;
    if (this.attributeSize * 4 > this.attributeBuffer.size) {
      this._resizeAttributeBuffer(this.attributeSize * 4);
    }
    if (this.indexSize > this.indexBuffer.length) {
      this._resizeIndexBuffer(this.indexSize);
    }
    const f32 = this.attributeBuffer.float32View;
    const u32 = this.attributeBuffer.uint32View;
    const indexBuffer = this.indexBuffer;
    let size = this._batchIndexSize;
    let start = this._batchIndexStart;
    let action = "startBatch";
    let batchElements = [];
    const maxTextures = this.maxTextures;
    for (let i = this.elementStart; i < this.elementSize; ++i) {
      const element = elements[i];
      elements[i] = null;
      const texture = element.texture;
      const source = texture._source;
      const adjustedBlendMode = getAdjustedBlendModeBlend(element.blendMode, source);
      const breakRequired = blendMode !== adjustedBlendMode || topology !== element.topology;
      if (source._batchTick === BATCH_TICK && !breakRequired) {
        element._textureId = source._textureBindLocation;
        size += element.indexSize;
        if (element.packAsQuad) {
          this.packQuadAttributes(
            element,
            f32,
            u32,
            element._attributeStart,
            element._textureId
          );
          this.packQuadIndex(
            indexBuffer,
            element._indexStart,
            element._attributeStart / this.vertexSize
          );
        } else {
          this.packAttributes(
            element,
            f32,
            u32,
            element._attributeStart,
            element._textureId
          );
          this.packIndex(
            element,
            indexBuffer,
            element._indexStart,
            element._attributeStart / this.vertexSize
          );
        }
        element._batch = batch;
        batchElements.push(element);
        continue;
      }
      source._batchTick = BATCH_TICK;
      if (textureBatch.count >= maxTextures || breakRequired) {
        this._finishBatch(
          batch,
          start,
          size - start,
          textureBatch,
          blendMode,
          topology,
          instructionSet,
          action,
          batchElements
        );
        action = "renderBatch";
        start = size;
        blendMode = adjustedBlendMode;
        topology = element.topology;
        batch = getBatchFromPool();
        textureBatch = batch.textures;
        textureBatch.clear();
        batchElements = [];
        ++BATCH_TICK;
      }
      element._textureId = source._textureBindLocation = textureBatch.count;
      textureBatch.ids[source.uid] = textureBatch.count;
      textureBatch.textures[textureBatch.count++] = source;
      element._batch = batch;
      batchElements.push(element);
      size += element.indexSize;
      if (element.packAsQuad) {
        this.packQuadAttributes(
          element,
          f32,
          u32,
          element._attributeStart,
          element._textureId
        );
        this.packQuadIndex(
          indexBuffer,
          element._indexStart,
          element._attributeStart / this.vertexSize
        );
      } else {
        this.packAttributes(
          element,
          f32,
          u32,
          element._attributeStart,
          element._textureId
        );
        this.packIndex(
          element,
          indexBuffer,
          element._indexStart,
          element._attributeStart / this.vertexSize
        );
      }
    }
    if (textureBatch.count > 0) {
      this._finishBatch(
        batch,
        start,
        size - start,
        textureBatch,
        blendMode,
        topology,
        instructionSet,
        action,
        batchElements
      );
      start = size;
      ++BATCH_TICK;
    }
    this.elementStart = this.elementSize;
    this._batchIndexStart = start;
    this._batchIndexSize = size;
  }
  _finishBatch(batch, indexStart, indexSize, textureBatch, blendMode, topology, instructionSet, action, elements) {
    batch.gpuBindGroup = null;
    batch.bindGroup = null;
    batch.action = action;
    batch.batcher = this;
    batch.textures = textureBatch;
    batch.blendMode = blendMode;
    batch.topology = topology;
    batch.start = indexStart;
    batch.size = indexSize;
    batch.elements = elements;
    ++BATCH_TICK;
    this.batches[this.batchIndex++] = batch;
    instructionSet.add(batch);
  }
  finish(instructionSet) {
    this.break(instructionSet);
  }
  /**
   * Resizes the attribute buffer to the given size (1 = 1 float32)
   * @param size - the size in vertices to ensure (not bytes!)
   */
  ensureAttributeBuffer(size) {
    if (size * 4 <= this.attributeBuffer.size) return;
    this._resizeAttributeBuffer(size * 4);
  }
  /**
   * Resizes the index buffer to the given size (1 = 1 float32)
   * @param size - the size in vertices to ensure (not bytes!)
   */
  ensureIndexBuffer(size) {
    if (size <= this.indexBuffer.length) return;
    this._resizeIndexBuffer(size);
  }
  _resizeAttributeBuffer(size) {
    const newSize = Math.max(size, this.attributeBuffer.size * 2);
    const newArrayBuffer = new ViewableBuffer(newSize);
    fastCopy(this.attributeBuffer.rawBinaryData, newArrayBuffer.rawBinaryData);
    this.attributeBuffer = newArrayBuffer;
  }
  _resizeIndexBuffer(size) {
    const indexBuffer = this.indexBuffer;
    let newSize = Math.max(size, indexBuffer.length * 1.5);
    newSize += newSize % 2;
    const newIndexBuffer = newSize > 65535 ? new Uint32Array(newSize) : new Uint16Array(newSize);
    if (newIndexBuffer.BYTES_PER_ELEMENT !== indexBuffer.BYTES_PER_ELEMENT) {
      for (let i = 0; i < indexBuffer.length; i++) {
        newIndexBuffer[i] = indexBuffer[i];
      }
    } else {
      fastCopy(indexBuffer.buffer, newIndexBuffer.buffer);
    }
    this.indexBuffer = newIndexBuffer;
  }
  packQuadIndex(indexBuffer, index, indicesOffset) {
    indexBuffer[index] = indicesOffset + 0;
    indexBuffer[index + 1] = indicesOffset + 1;
    indexBuffer[index + 2] = indicesOffset + 2;
    indexBuffer[index + 3] = indicesOffset + 0;
    indexBuffer[index + 4] = indicesOffset + 2;
    indexBuffer[index + 5] = indicesOffset + 3;
  }
  packIndex(element, indexBuffer, index, indicesOffset) {
    const indices = element.indices;
    const size = element.indexSize;
    const indexOffset = element.indexOffset;
    const attributeOffset = element.attributeOffset;
    for (let i = 0; i < size; i++) {
      indexBuffer[index++] = indicesOffset + indices[i + indexOffset] - attributeOffset;
    }
  }
  /**
   * Destroys the batch and its resources.
   * @param options - destruction options
   * @param options.shader - whether to destroy the associated shader
   */
  destroy(options = {}) {
    if (this.batches === null) return;
    for (let i = 0; i < this.batchIndex; i++) {
      returnBatchToPool(this.batches[i]);
    }
    this.batches = null;
    this.geometry.destroy(true);
    this.geometry = null;
    if (options.shader) {
      this.shader?.destroy();
      this.shader = null;
    }
    for (let i = 0; i < this._elements.length; i++) {
      if (this._elements[i]) this._elements[i]._batch = null;
    }
    this._elements = null;
    this.indexBuffer = null;
    this.attributeBuffer.destroy();
    this.attributeBuffer = null;
  }
};
_Batcher.defaultOptions = {
  maxTextures: null,
  attributesInitialSize: 4,
  indicesInitialSize: 6
};
var Batcher = _Batcher;

// scripts/folia/node_modules/pixi.js/lib/rendering/batcher/shared/BatchGeometry.mjs
var placeHolderBufferData = new Float32Array(1);
var placeHolderIndexData = new Uint32Array(1);
var BatchGeometry = class extends Geometry {
  constructor() {
    const vertexSize = 6;
    const attributeBuffer = new Buffer({
      data: placeHolderBufferData,
      label: "attribute-batch-buffer",
      usage: BufferUsage.VERTEX | BufferUsage.COPY_DST,
      shrinkToFit: false
    });
    const indexBuffer = new Buffer({
      data: placeHolderIndexData,
      label: "index-batch-buffer",
      usage: BufferUsage.INDEX | BufferUsage.COPY_DST,
      // | BufferUsage.STATIC,
      shrinkToFit: false
    });
    const stride = vertexSize * 4;
    super({
      attributes: {
        aPosition: {
          buffer: attributeBuffer,
          format: "float32x2",
          stride,
          offset: 0
        },
        aUV: {
          buffer: attributeBuffer,
          format: "float32x2",
          stride,
          offset: 2 * 4
        },
        aColor: {
          buffer: attributeBuffer,
          format: "unorm8x4",
          stride,
          offset: 4 * 4
        },
        aTextureIdAndRound: {
          buffer: attributeBuffer,
          format: "uint16x2",
          stride,
          offset: 5 * 4
        }
      },
      indexBuffer
    });
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/getBatchSamplersUniformGroup.mjs
var batchSamplersUniformGroupHash = {};
function getBatchSamplersUniformGroup(maxTextures) {
  let batchSamplersUniformGroup = batchSamplersUniformGroupHash[maxTextures];
  if (batchSamplersUniformGroup) return batchSamplersUniformGroup;
  const sampleValues = new Int32Array(maxTextures);
  for (let i = 0; i < maxTextures; i++) {
    sampleValues[i] = i;
  }
  batchSamplersUniformGroup = batchSamplersUniformGroupHash[maxTextures] = new UniformGroup({
    uTextures: { value: sampleValues, type: `i32`, size: maxTextures }
  }, { isStatic: true });
  return batchSamplersUniformGroup;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/batcher/shared/DefaultShader.mjs
var DefaultShader = class extends Shader {
  constructor(maxTextures) {
    const glProgram = compileHighShaderGlProgram({
      name: "batch",
      bits: [
        colorBitGl,
        generateTextureBatchBitGl(maxTextures),
        roundPixelsBitGl
      ]
    });
    const gpuProgram = compileHighShaderGpuProgram({
      name: "batch",
      bits: [
        colorBit,
        generateTextureBatchBit(maxTextures),
        roundPixelsBit
      ]
    });
    super({
      glProgram,
      gpuProgram,
      resources: {
        batchSamplers: getBatchSamplersUniformGroup(maxTextures)
      }
    });
    this.maxTextures = maxTextures;
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/batcher/shared/DefaultBatcher.mjs
var defaultShader = null;
var _DefaultBatcher = class _DefaultBatcher2 extends Batcher {
  constructor(options) {
    super(options);
    this.geometry = new BatchGeometry();
    this.name = _DefaultBatcher2.extension.name;
    this.vertexSize = 6;
    defaultShader ?? (defaultShader = new DefaultShader(options.maxTextures));
    this.shader = defaultShader;
  }
  /**
   * Packs the attributes of a DefaultBatchableMeshElement into the provided views.
   * @param element - The DefaultBatchableMeshElement to pack.
   * @param float32View - The Float32Array view to pack into.
   * @param uint32View - The Uint32Array view to pack into.
   * @param index - The starting index in the views.
   * @param textureId - The texture ID to use.
   */
  packAttributes(element, float32View, uint32View, index, textureId) {
    const textureIdAndRound = textureId << 16 | element.roundPixels & 65535;
    const wt = element.transform;
    const a = wt.a;
    const b = wt.b;
    const c = wt.c;
    const d = wt.d;
    const tx = wt.tx;
    const ty = wt.ty;
    const { positions, uvs } = element;
    const argb = element.color;
    const offset = element.attributeOffset;
    const end = offset + element.attributeSize;
    for (let i = offset; i < end; i++) {
      const i2 = i * 2;
      const x = positions[i2];
      const y = positions[i2 + 1];
      float32View[index++] = a * x + c * y + tx;
      float32View[index++] = d * y + b * x + ty;
      float32View[index++] = uvs[i2];
      float32View[index++] = uvs[i2 + 1];
      uint32View[index++] = argb;
      uint32View[index++] = textureIdAndRound;
    }
  }
  /**
   * Packs the attributes of a DefaultBatchableQuadElement into the provided views.
   * @param element - The DefaultBatchableQuadElement to pack.
   * @param float32View - The Float32Array view to pack into.
   * @param uint32View - The Uint32Array view to pack into.
   * @param index - The starting index in the views.
   * @param textureId - The texture ID to use.
   */
  packQuadAttributes(element, float32View, uint32View, index, textureId) {
    const texture = element.texture;
    const wt = element.transform;
    const a = wt.a;
    const b = wt.b;
    const c = wt.c;
    const d = wt.d;
    const tx = wt.tx;
    const ty = wt.ty;
    const bounds = element.bounds;
    const w0 = bounds.maxX;
    const w1 = bounds.minX;
    const h0 = bounds.maxY;
    const h1 = bounds.minY;
    const uvs = texture.uvs;
    const argb = element.color;
    const textureIdAndRound = textureId << 16 | element.roundPixels & 65535;
    float32View[index + 0] = a * w1 + c * h1 + tx;
    float32View[index + 1] = d * h1 + b * w1 + ty;
    float32View[index + 2] = uvs.x0;
    float32View[index + 3] = uvs.y0;
    uint32View[index + 4] = argb;
    uint32View[index + 5] = textureIdAndRound;
    float32View[index + 6] = a * w0 + c * h1 + tx;
    float32View[index + 7] = d * h1 + b * w0 + ty;
    float32View[index + 8] = uvs.x1;
    float32View[index + 9] = uvs.y1;
    uint32View[index + 10] = argb;
    uint32View[index + 11] = textureIdAndRound;
    float32View[index + 12] = a * w0 + c * h0 + tx;
    float32View[index + 13] = d * h0 + b * w0 + ty;
    float32View[index + 14] = uvs.x2;
    float32View[index + 15] = uvs.y2;
    uint32View[index + 16] = argb;
    uint32View[index + 17] = textureIdAndRound;
    float32View[index + 18] = a * w1 + c * h0 + tx;
    float32View[index + 19] = d * h0 + b * w1 + ty;
    float32View[index + 20] = uvs.x3;
    float32View[index + 21] = uvs.y3;
    uint32View[index + 22] = argb;
    uint32View[index + 23] = textureIdAndRound;
  }
  /**
   * Updates the maximum number of textures that can be used in the shader.
   * @param maxTextures - The maximum number of textures that can be used in the shader.
   * @internal
   */
  _updateMaxTextures(maxTextures) {
    if (this.shader.maxTextures === maxTextures) return;
    defaultShader = new DefaultShader(maxTextures);
    this.shader = defaultShader;
  }
  destroy() {
    this.shader = null;
    super.destroy();
  }
};
_DefaultBatcher.extension = {
  type: [
    ExtensionType.Batcher
  ],
  name: "default"
};
var DefaultBatcher = _DefaultBatcher;

// scripts/folia/node_modules/pixi.js/lib/utils/data/GCManagedHash.mjs
var GCManagedHash = class {
  constructor(options) {
    this.items = /* @__PURE__ */ Object.create(null);
    const { renderer, type, onUnload, priority, name } = options;
    this._renderer = renderer;
    renderer.gc.addResourceHash(this, "items", type, priority ?? 0);
    this._onUnload = onUnload;
    this.name = name;
  }
  /**
   * Add an item to the hash. No-op if already added.
   * @param item
   * @returns true if the item was added, false if it was already in the hash
   */
  add(item) {
    if (this.items[item.uid]) return false;
    this.items[item.uid] = item;
    item.once("unload", this.remove, this);
    item._gcLastUsed = this._renderer.gc.now;
    return true;
  }
  remove(item, ...args) {
    if (!this.items[item.uid]) return;
    const gpuData = item._gpuData[this._renderer.uid];
    if (!gpuData) return;
    this._onUnload?.(item, ...args);
    item.off("unload", this.remove, this);
    gpuData.destroy();
    item._gpuData[this._renderer.uid] = null;
    this.items[item.uid] = null;
  }
  removeAll(...args) {
    Object.values(this.items).forEach((item) => item && this.remove(item, ...args));
  }
  destroy(...args) {
    this.removeAll(...args);
    this.items = /* @__PURE__ */ Object.create(null);
    this._renderer = null;
    this._onUnload = null;
  }
};

export {
  addBits,
  compileHooks,
  compileInputs,
  compileOutputs,
  injectBits,
  compileHighShader,
  compileHighShaderGl,
  vertexGPUTemplate,
  fragmentGPUTemplate,
  vertexGlTemplate,
  fragmentGlTemplate,
  globalUniformsBit,
  globalUniformsUBOBitGl,
  globalUniformsBitGl,
  compileHighShaderGpuProgram,
  compileHighShaderGlProgram,
  colorBit,
  colorBitGl,
  generateTextureBatchBit,
  generateTextureBatchBitGl,
  roundPixelsBit,
  roundPixelsBitGl,
  fastCopy,
  BLEND_TO_NPM,
  STENCIL_MODES,
  getAdjustedBlendModeBlend,
  checkMaxIfStatementsInShader,
  getMaxTexturesPerBatch,
  BatchTextureArray,
  Batch,
  Batcher,
  BatchGeometry,
  getBatchSamplersUniformGroup,
  DefaultShader,
  DefaultBatcher,
  GCManagedHash
};
