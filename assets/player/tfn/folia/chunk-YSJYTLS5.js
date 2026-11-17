// Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; adapted for TuneFreeNext. See THIRD_PARTY_NOTICES.md and scripts/vendor_folia_skins.mjs.
import {
  BufferResource,
  UboSystem,
  compileBufferSync,
  uboSyncFunctionsSTD40,
  uniformParsers
} from "./chunk-I4JNEM5R.js";
import {
  ExtensionType,
  TextureSource,
  UniformGroup,
  eventemitter3_default,
  getAttributeInfoFromFormat,
  uid,
  warn
} from "./chunk-NJ7XHR5M.js";

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/utils/createUboElementsSTD40.mjs
var WGSL_TO_STD40_SIZE = {
  f32: 4,
  i32: 4,
  "vec2<f32>": 8,
  "vec3<f32>": 12,
  "vec4<f32>": 16,
  "vec2<i32>": 8,
  "vec3<i32>": 12,
  "vec4<i32>": 16,
  u32: 4,
  "vec2<u32>": 8,
  "vec3<u32>": 12,
  "vec4<u32>": 16,
  "mat2x2<f32>": 16 * 2,
  "mat3x3<f32>": 16 * 3,
  "mat4x4<f32>": 16 * 4
  // TODO - not essential for now but support these in the future
  // int:      4,
  // ivec2:    8,
  // ivec3:    12,
  // ivec4:    16,
  // uint:     4,
  // uvec2:    8,
  // uvec3:    12,
  // uvec4:    16,
  // bool:     4,
  // bvec2:    8,
  // bvec3:    12,
  // bvec4:    16,
  // mat2:     16 * 2,
  // mat3:     16 * 3,
  // mat4:     16 * 4,
};
function createUboElementsSTD40(uniformData) {
  const uboElements = uniformData.map((data) => ({
    data,
    offset: 0,
    size: 0
  }));
  const chunkSize = 16;
  let size = 0;
  let offset = 0;
  for (let i = 0; i < uboElements.length; i++) {
    const uboElement = uboElements[i];
    size = WGSL_TO_STD40_SIZE[uboElement.data.type];
    if (!size) {
      throw new Error(`Unknown type ${uboElement.data.type}`);
    }
    if (uboElement.data.size > 1) {
      size = Math.max(size, chunkSize) * uboElement.data.size;
    }
    const boundary = size === 12 ? 16 : size;
    uboElement.size = size;
    const curOffset = offset % chunkSize;
    if (curOffset > 0 && chunkSize - curOffset < boundary) {
      offset += (chunkSize - curOffset) % 16;
    } else {
      offset += (size - curOffset % size) % size;
    }
    uboElement.offset = offset;
    offset += size;
  }
  offset = Math.ceil(offset / 16) * 16;
  return { uboElements, size: offset };
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/utils/generateArraySyncSTD40.mjs
function generateArraySyncSTD40(uboElement, offsetToAdd) {
  const rowSize = Math.max(WGSL_TO_STD40_SIZE[uboElement.data.type] / 16, 1);
  const elementSize = uboElement.data.value.length / uboElement.data.size;
  const remainder = (4 - elementSize % 4) % 4;
  const data = uboElement.data.type.indexOf("i32") >= 0 ? "dataInt32" : "data";
  return `
        v = uv.${uboElement.data.name};
        offset += ${offsetToAdd};

        arrayOffset = offset;

        t = 0;

        for(var i=0; i < ${uboElement.data.size * rowSize}; i++)
        {
            for(var j = 0; j < ${elementSize}; j++)
            {
                ${data}[arrayOffset++] = v[t++];
            }
            ${remainder !== 0 ? `arrayOffset += ${remainder};` : ""}
        }
    `;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/utils/createUboSyncSTD40.mjs
function createUboSyncFunctionSTD40(uboElements) {
  return compileBufferSync(
    uboElements,
    uboSyncFunctionsSTD40,
    generateArraySyncSTD40
  );
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/GlUboSystem.mjs
var GlUboSystem = class extends UboSystem {
  constructor() {
    super({
      createUboElements: createUboElementsSTD40,
      generateUboSync: createUboSyncFunctionSTD40
    });
  }
};
GlUboSystem.extension = {
  type: [ExtensionType.WebGLSystem],
  name: "ubo"
};

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/shared/texture/TextureView.mjs
var TextureView = class extends eventemitter3_default {
  /**
   * @param source - The texture source to view.
   * @param viewDescriptor - The WebGPU texture view descriptor.
   */
  constructor(source, viewDescriptor) {
    super();
    this._resourceType = "textureView";
    this._resourceId = uid("resource");
    this.source = source;
    this.viewDescriptor = viewDescriptor;
    this._onChange = this._onChange.bind(this);
    this._onDestroy = this._onDestroy.bind(this);
    this.source.on("change", this._onChange);
    this.source.on("destroy", this._onDestroy);
  }
  _onChange() {
    this.emit("change", this);
  }
  _onDestroy() {
    this.destroy();
  }
  /** Returns whether the underlying source is destroyed. */
  get destroyed() {
    return this.source.destroyed;
  }
  /** Destroys the view and cleans up event listeners. */
  destroy() {
    if (this.source) {
      this.source.off("change", this._onChange);
      this.source.off("destroy", this._onDestroy);
    }
    this.emit("destroy", this);
    this.removeAllListeners();
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/GenerateShaderSyncCode.mjs
function generateShaderSyncCode(shader, shaderSystem) {
  const funcFragments = [];
  const headerFragments = [`
        var g = s.groups;
        var sS = r.shader;
        var p = s.glProgram;
        var ugS = r.uniformGroup;
        var resources;
    `];
  let addedTextureSystem = false;
  let textureCount = 0;
  const programData = shaderSystem._getProgramData(shader.glProgram);
  for (const i in shader.groups) {
    const group = shader.groups[i];
    funcFragments.push(`
            resources = g[${i}].resources;
        `);
    for (const j in group.resources) {
      const resource = group.resources[j];
      if (resource instanceof UniformGroup) {
        if (resource.ubo) {
          const resName = shader._uniformBindMap[i][Number(j)];
          funcFragments.push(`
                        sS.bindUniformBlock(
                            resources[${j}],
                            '${resName}',
                            ${shader.glProgram._uniformBlockData[resName].index}
                        );
                    `);
        } else {
          funcFragments.push(`
                        ugS.updateUniformGroup(resources[${j}], p, sD);
                    `);
        }
      } else if (resource instanceof BufferResource) {
        const resName = shader._uniformBindMap[i][Number(j)];
        funcFragments.push(`
                    sS.bindUniformBlock(
                        resources[${j}],
                        '${resName}',
                        ${shader.glProgram._uniformBlockData[resName].index}
                    );
                `);
      } else if (resource instanceof TextureSource || resource instanceof TextureView) {
        const uniformName = shader._uniformBindMap[i][j];
        const uniformData = programData.uniformData[uniformName];
        if (uniformData) {
          if (!addedTextureSystem) {
            addedTextureSystem = true;
            headerFragments.push(`
                        var tS = r.texture;
                        `);
          }
          shaderSystem._gl.uniform1i(uniformData.location, textureCount);
          funcFragments.push(`
                        tS.bind(resources[${j}], ${textureCount});
                    `);
          textureCount++;
        }
      }
    }
  }
  const functionSource = [...headerFragments, ...funcFragments].join("\n");
  return new Function("r", "s", "sD", functionSource);
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/GlProgramData.mjs
var IGLUniformData = class {
};
var GlProgramData = class {
  /**
   * Makes a new Pixi program.
   * @param program - webgl program
   * @param uniformData - uniforms
   */
  constructor(program, uniformData) {
    this.program = program;
    this.uniformData = uniformData;
    this.uniformGroups = {};
    this.uniformDirtyGroups = {};
    this.uniformBlockBindings = {};
  }
  /** Destroys this program. */
  destroy() {
    this.uniformData = null;
    this.uniformGroups = null;
    this.uniformDirtyGroups = null;
    this.uniformBlockBindings = null;
    this.program = null;
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/compileShader.mjs
function compileShader(gl, type, src) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, src);
  gl.compileShader(shader);
  return shader;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/defaultValue.mjs
function booleanArray(size) {
  const array = new Array(size);
  for (let i = 0; i < array.length; i++) {
    array[i] = false;
  }
  return array;
}
function defaultValue(type, size) {
  switch (type) {
    case "float":
      return 0;
    case "vec2":
      return new Float32Array(2 * size);
    case "vec3":
      return new Float32Array(3 * size);
    case "vec4":
      return new Float32Array(4 * size);
    case "int":
    case "uint":
    case "sampler2D":
    case "sampler2DArray":
      return 0;
    case "ivec2":
      return new Int32Array(2 * size);
    case "ivec3":
      return new Int32Array(3 * size);
    case "ivec4":
      return new Int32Array(4 * size);
    case "uvec2":
      return new Uint32Array(2 * size);
    case "uvec3":
      return new Uint32Array(3 * size);
    case "uvec4":
      return new Uint32Array(4 * size);
    case "bool":
      return false;
    case "bvec2":
      return booleanArray(2 * size);
    case "bvec3":
      return booleanArray(3 * size);
    case "bvec4":
      return booleanArray(4 * size);
    case "mat2":
      return new Float32Array([
        1,
        0,
        0,
        1
      ]);
    case "mat3":
      return new Float32Array([
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1
      ]);
    case "mat4":
      return new Float32Array([
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1
      ]);
  }
  return null;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/mapType.mjs
var GL_TABLE = null;
var GL_TO_GLSL_TYPES = {
  FLOAT: "float",
  FLOAT_VEC2: "vec2",
  FLOAT_VEC3: "vec3",
  FLOAT_VEC4: "vec4",
  INT: "int",
  INT_VEC2: "ivec2",
  INT_VEC3: "ivec3",
  INT_VEC4: "ivec4",
  UNSIGNED_INT: "uint",
  UNSIGNED_INT_VEC2: "uvec2",
  UNSIGNED_INT_VEC3: "uvec3",
  UNSIGNED_INT_VEC4: "uvec4",
  BOOL: "bool",
  BOOL_VEC2: "bvec2",
  BOOL_VEC3: "bvec3",
  BOOL_VEC4: "bvec4",
  FLOAT_MAT2: "mat2",
  FLOAT_MAT3: "mat3",
  FLOAT_MAT4: "mat4",
  SAMPLER_2D: "sampler2D",
  INT_SAMPLER_2D: "sampler2D",
  UNSIGNED_INT_SAMPLER_2D: "sampler2D",
  SAMPLER_2D_SHADOW: "sampler2DShadow",
  SAMPLER_CUBE: "samplerCube",
  INT_SAMPLER_CUBE: "samplerCube",
  UNSIGNED_INT_SAMPLER_CUBE: "samplerCube",
  SAMPLER_CUBE_SHADOW: "samplerCubeShadow",
  SAMPLER_2D_ARRAY: "sampler2DArray",
  INT_SAMPLER_2D_ARRAY: "sampler2DArray",
  UNSIGNED_INT_SAMPLER_2D_ARRAY: "sampler2DArray",
  SAMPLER_2D_ARRAY_SHADOW: "sampler2DArrayShadow"
};
var GLSL_TO_VERTEX_TYPES = {
  float: "float32",
  vec2: "float32x2",
  vec3: "float32x3",
  vec4: "float32x4",
  int: "sint32",
  ivec2: "sint32x2",
  ivec3: "sint32x3",
  ivec4: "sint32x4",
  uint: "uint32",
  uvec2: "uint32x2",
  uvec3: "uint32x3",
  uvec4: "uint32x4",
  bool: "uint32",
  bvec2: "uint32x2",
  bvec3: "uint32x3",
  bvec4: "uint32x4"
};
function mapType(gl, type) {
  if (!GL_TABLE) {
    const typeNames = Object.keys(GL_TO_GLSL_TYPES);
    GL_TABLE = {};
    for (let i = 0; i < typeNames.length; ++i) {
      const tn = typeNames[i];
      GL_TABLE[gl[tn]] = GL_TO_GLSL_TYPES[tn];
    }
  }
  return GL_TABLE[type];
}
function mapGlToVertexFormat(gl, type) {
  const typeValue = mapType(gl, type);
  return GLSL_TO_VERTEX_TYPES[typeValue] || "float32";
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/extractAttributesFromGlProgram.mjs
function extractAttributesFromGlProgram(program, gl, sortAttributes = false) {
  const attributes = {};
  const totalAttributes = gl.getProgramParameter(program, gl.ACTIVE_ATTRIBUTES);
  for (let i = 0; i < totalAttributes; i++) {
    const attribData = gl.getActiveAttrib(program, i);
    if (attribData.name.startsWith("gl_")) {
      continue;
    }
    const format = mapGlToVertexFormat(gl, attribData.type);
    attributes[attribData.name] = {
      location: 0,
      // set further down..
      format,
      stride: getAttributeInfoFromFormat(format).stride,
      offset: 0,
      instance: false,
      start: 0
    };
  }
  const keys = Object.keys(attributes);
  if (sortAttributes) {
    keys.sort((a, b) => a > b ? 1 : -1);
    for (let i = 0; i < keys.length; i++) {
      attributes[keys[i]].location = i;
      gl.bindAttribLocation(program, i, keys[i]);
    }
    gl.linkProgram(program);
  } else {
    for (let i = 0; i < keys.length; i++) {
      attributes[keys[i]].location = gl.getAttribLocation(program, keys[i]);
    }
  }
  return attributes;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/getUboData.mjs
function getUboData(program, gl) {
  if (!gl.ACTIVE_UNIFORM_BLOCKS) return {};
  const uniformBlocks = {};
  const totalUniformsBlocks = gl.getProgramParameter(program, gl.ACTIVE_UNIFORM_BLOCKS);
  for (let i = 0; i < totalUniformsBlocks; i++) {
    const name = gl.getActiveUniformBlockName(program, i);
    const uniformBlockIndex = gl.getUniformBlockIndex(program, name);
    const size = gl.getActiveUniformBlockParameter(program, i, gl.UNIFORM_BLOCK_DATA_SIZE);
    uniformBlocks[name] = {
      name,
      index: uniformBlockIndex,
      size
    };
  }
  return uniformBlocks;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/getUniformData.mjs
function getUniformData(program, gl) {
  const uniforms = {};
  const totalUniforms = gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS);
  for (let i = 0; i < totalUniforms; i++) {
    const uniformData = gl.getActiveUniform(program, i);
    const name = uniformData.name.replace(/\[.*?\]$/, "");
    const isArray = !!uniformData.name.match(/\[.*?\]$/);
    const type = mapType(gl, uniformData.type);
    uniforms[name] = {
      name,
      index: i,
      type,
      size: uniformData.size,
      isArray,
      value: defaultValue(type, uniformData.size)
    };
  }
  return uniforms;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/logProgramError.mjs
function logPrettyShaderError(gl, shader) {
  const rawSource = gl.getShaderSource(shader);
  if (rawSource === null) {
    console.error("PixiJS Error: Could not retrieve shader source (WebGL context may be lost).");
    return;
  }
  const shaderSrc = rawSource.split("\n").map((line, index) => `${index}: ${line}`);
  const shaderLog = gl.getShaderInfoLog(shader) ?? "";
  const splitShader = shaderLog.split("\n");
  const dedupe = {};
  const lineNumbers = splitShader.map((line) => parseFloat(line.replace(/^ERROR\: 0\:([\d]+)\:.*$/, "$1"))).filter((n) => {
    if (n && !dedupe[n]) {
      dedupe[n] = true;
      return true;
    }
    return false;
  });
  const logArgs = [""];
  lineNumbers.forEach((number) => {
    shaderSrc[number - 1] = `%c${shaderSrc[number - 1]}%c`;
    logArgs.push("background: #FF0000; color:#FFFFFF; font-size: 10px", "font-size: 10px");
  });
  const fragmentSourceToLog = shaderSrc.join("\n");
  logArgs[0] = fragmentSourceToLog;
  console.error(shaderLog);
  console.groupCollapsed("click to view full shader code");
  console.warn(...logArgs);
  console.groupEnd();
}
function logProgramError(gl, program, vertexShader, fragmentShader) {
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    if (!gl.getShaderParameter(vertexShader, gl.COMPILE_STATUS)) {
      logPrettyShaderError(gl, vertexShader);
    }
    if (!gl.getShaderParameter(fragmentShader, gl.COMPILE_STATUS)) {
      logPrettyShaderError(gl, fragmentShader);
    }
    console.error("PixiJS Error: Could not initialize shader.");
    if (gl.getProgramInfoLog(program) !== "") {
      console.warn("PixiJS Warning: gl.getProgramInfoLog()", gl.getProgramInfoLog(program));
    }
  }
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/generateProgram.mjs
function generateProgram(gl, program) {
  const glVertShader = compileShader(gl, gl.VERTEX_SHADER, program.vertex);
  const glFragShader = compileShader(gl, gl.FRAGMENT_SHADER, program.fragment);
  const webGLProgram = gl.createProgram();
  gl.attachShader(webGLProgram, glVertShader);
  gl.attachShader(webGLProgram, glFragShader);
  const transformFeedbackVaryings = program.transformFeedbackVaryings;
  if (transformFeedbackVaryings) {
    if (typeof gl.transformFeedbackVaryings !== "function") {
      warn(`TransformFeedback is not supported but TransformFeedbackVaryings are given.`);
    } else {
      gl.transformFeedbackVaryings(
        webGLProgram,
        transformFeedbackVaryings.names,
        transformFeedbackVaryings.bufferMode === "separate" ? gl.SEPARATE_ATTRIBS : gl.INTERLEAVED_ATTRIBS
      );
    }
  }
  gl.linkProgram(webGLProgram);
  if (!gl.getProgramParameter(webGLProgram, gl.LINK_STATUS)) {
    logProgramError(gl, webGLProgram, glVertShader, glFragShader);
  }
  program._attributeData = extractAttributesFromGlProgram(
    webGLProgram,
    gl,
    !/^[ \t]*#[ \t]*version[ \t]+300[ \t]+es[ \t]*$/m.test(program.vertex)
  );
  program._uniformData = getUniformData(webGLProgram, gl);
  program._uniformBlockData = getUboData(webGLProgram, gl);
  gl.deleteShader(glVertShader);
  gl.deleteShader(glFragShader);
  const uniformData = {};
  for (const i in program._uniformData) {
    const data = program._uniformData[i];
    uniformData[i] = {
      location: gl.getUniformLocation(webGLProgram, i),
      value: defaultValue(data.type, data.size)
    };
  }
  const glProgram = new GlProgramData(webGLProgram, uniformData);
  return glProgram;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/GlShaderSystem.mjs
var defaultSyncData = {
  textureCount: 0,
  blockIndex: 0
};
var GlShaderSystem = class {
  constructor(renderer) {
    this._activeProgram = null;
    this._programDataHash = /* @__PURE__ */ Object.create(null);
    this._shaderSyncFunctions = /* @__PURE__ */ Object.create(null);
    this._renderer = renderer;
  }
  contextChange(gl) {
    this._gl = gl;
    this._programDataHash = /* @__PURE__ */ Object.create(null);
    this._shaderSyncFunctions = /* @__PURE__ */ Object.create(null);
    this._activeProgram = null;
  }
  /**
   * Changes the current shader to the one given in parameter.
   * @param shader - the new shader
   * @param skipSync - false if the shader should automatically sync its uniforms.
   * @returns the glProgram that belongs to the shader.
   */
  bind(shader, skipSync) {
    this._setProgram(shader.glProgram);
    if (skipSync) return;
    defaultSyncData.textureCount = 0;
    defaultSyncData.blockIndex = 0;
    let syncFunction = this._shaderSyncFunctions[shader.glProgram._key];
    if (!syncFunction) {
      syncFunction = this._shaderSyncFunctions[shader.glProgram._key] = this._generateShaderSync(shader, this);
    }
    this._renderer.buffer.nextBindBase(!!shader.glProgram.transformFeedbackVaryings);
    syncFunction(this._renderer, shader, defaultSyncData);
  }
  /**
   * Updates the uniform group.
   * @param uniformGroup - the uniform group to update
   */
  updateUniformGroup(uniformGroup) {
    this._renderer.uniformGroup.updateUniformGroup(uniformGroup, this._activeProgram, defaultSyncData);
  }
  /**
   * Binds a uniform block to the shader.
   * @param uniformGroup - the uniform group to bind
   * @param name - the name of the uniform block
   * @param index - the index of the uniform block
   */
  bindUniformBlock(uniformGroup, name, index = 0) {
    const bufferSystem = this._renderer.buffer;
    const programData = this._getProgramData(this._activeProgram);
    const isBufferResource = uniformGroup._bufferResource;
    if (!isBufferResource) {
      this._renderer.ubo.updateUniformGroup(uniformGroup);
    }
    const buffer = uniformGroup.buffer;
    const glBuffer = bufferSystem.updateBuffer(buffer);
    const boundLocation = bufferSystem.freeLocationForBufferBase(glBuffer);
    if (isBufferResource) {
      const { offset, size } = uniformGroup;
      if (offset === 0 && size === buffer.data.byteLength) {
        bufferSystem.bindBufferBase(glBuffer, boundLocation);
      } else {
        bufferSystem.bindBufferRange(glBuffer, boundLocation, offset);
      }
    } else if (bufferSystem.getLastBindBaseLocation(glBuffer) !== boundLocation) {
      bufferSystem.bindBufferBase(glBuffer, boundLocation);
    }
    const uniformBlockIndex = this._activeProgram._uniformBlockData[name].index;
    if (programData.uniformBlockBindings[index] === boundLocation) return;
    programData.uniformBlockBindings[index] = boundLocation;
    this._renderer.gl.uniformBlockBinding(programData.program, uniformBlockIndex, boundLocation);
  }
  _setProgram(program) {
    if (this._activeProgram === program) return;
    this._activeProgram = program;
    const programData = this._getProgramData(program);
    this._gl.useProgram(programData.program);
  }
  /**
   * @param program - the program to get the data for
   * @internal
   */
  _getProgramData(program) {
    return this._programDataHash[program._key] || this._createProgramData(program);
  }
  _createProgramData(program) {
    const key = program._key;
    this._programDataHash[key] = generateProgram(this._gl, program);
    return this._programDataHash[key];
  }
  destroy() {
    for (const key of Object.keys(this._programDataHash)) {
      this._programDataHash[key].destroy();
    }
    this._programDataHash = null;
    this._shaderSyncFunctions = null;
    this._activeProgram = null;
    this._renderer = null;
    this._gl = null;
  }
  /**
   * Creates a function that can be executed that will sync the shader as efficiently as possible.
   * Overridden by the unsafe eval package if you don't want eval used in your project.
   * @param shader - the shader to generate the sync function for
   * @param shaderSystem - the shader system to use
   * @returns - the generated sync function
   * @ignore
   */
  _generateShaderSync(shader, shaderSystem) {
    return generateShaderSyncCode(shader, shaderSystem);
  }
  resetState() {
    this._activeProgram = null;
  }
};
GlShaderSystem.extension = {
  type: [
    ExtensionType.WebGLSystem
  ],
  name: "shader"
};

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/utils/generateUniformsSyncTypes.mjs
var UNIFORM_TO_SINGLE_SETTERS = {
  f32: `if (cv !== v) {
            cu.value = v;
            gl.uniform1f(location, v);
        }`,
  "vec2<f32>": `if (cv[0] !== v[0] || cv[1] !== v[1]) {
            cv[0] = v[0];
            cv[1] = v[1];
            gl.uniform2f(location, v[0], v[1]);
        }`,
  "vec3<f32>": `if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            gl.uniform3f(location, v[0], v[1], v[2]);
        }`,
  "vec4<f32>": `if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2] || cv[3] !== v[3]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            cv[3] = v[3];
            gl.uniform4f(location, v[0], v[1], v[2], v[3]);
        }`,
  i32: `if (cv !== v) {
            cu.value = v;
            gl.uniform1i(location, v);
        }`,
  "vec2<i32>": `if (cv[0] !== v[0] || cv[1] !== v[1]) {
            cv[0] = v[0];
            cv[1] = v[1];
            gl.uniform2i(location, v[0], v[1]);
        }`,
  "vec3<i32>": `if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            gl.uniform3i(location, v[0], v[1], v[2]);
        }`,
  "vec4<i32>": `if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2] || cv[3] !== v[3]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            cv[3] = v[3];
            gl.uniform4i(location, v[0], v[1], v[2], v[3]);
        }`,
  u32: `if (cv !== v) {
            cu.value = v;
            gl.uniform1ui(location, v);
        }`,
  "vec2<u32>": `if (cv[0] !== v[0] || cv[1] !== v[1]) {
            cv[0] = v[0];
            cv[1] = v[1];
            gl.uniform2ui(location, v[0], v[1]);
        }`,
  "vec3<u32>": `if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            gl.uniform3ui(location, v[0], v[1], v[2]);
        }`,
  "vec4<u32>": `if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2] || cv[3] !== v[3]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            cv[3] = v[3];
            gl.uniform4ui(location, v[0], v[1], v[2], v[3]);
        }`,
  bool: `if (cv !== v) {
            cu.value = v;
            gl.uniform1i(location, v);
        }`,
  "vec2<bool>": `if (cv[0] !== v[0] || cv[1] !== v[1]) {
            cv[0] = v[0];
            cv[1] = v[1];
            gl.uniform2i(location, v[0], v[1]);
        }`,
  "vec3<bool>": `if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            gl.uniform3i(location, v[0], v[1], v[2]);
        }`,
  "vec4<bool>": `if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2] || cv[3] !== v[3]) {
            cv[0] = v[0];
            cv[1] = v[1];
            cv[2] = v[2];
            cv[3] = v[3];
            gl.uniform4i(location, v[0], v[1], v[2], v[3]);
        }`,
  "mat2x2<f32>": `gl.uniformMatrix2fv(location, false, v);`,
  "mat3x3<f32>": `gl.uniformMatrix3fv(location, false, v);`,
  "mat4x4<f32>": `gl.uniformMatrix4fv(location, false, v);`
};
var UNIFORM_TO_ARRAY_SETTERS = {
  f32: `gl.uniform1fv(location, v);`,
  "vec2<f32>": `gl.uniform2fv(location, v);`,
  "vec3<f32>": `gl.uniform3fv(location, v);`,
  "vec4<f32>": `gl.uniform4fv(location, v);`,
  "mat2x2<f32>": `gl.uniformMatrix2fv(location, false, v);`,
  "mat3x3<f32>": `gl.uniformMatrix3fv(location, false, v);`,
  "mat4x4<f32>": `gl.uniformMatrix4fv(location, false, v);`,
  i32: `gl.uniform1iv(location, v);`,
  "vec2<i32>": `gl.uniform2iv(location, v);`,
  "vec3<i32>": `gl.uniform3iv(location, v);`,
  "vec4<i32>": `gl.uniform4iv(location, v);`,
  u32: `gl.uniform1iv(location, v);`,
  "vec2<u32>": `gl.uniform2iv(location, v);`,
  "vec3<u32>": `gl.uniform3iv(location, v);`,
  "vec4<u32>": `gl.uniform4iv(location, v);`,
  bool: `gl.uniform1iv(location, v);`,
  "vec2<bool>": `gl.uniform2iv(location, v);`,
  "vec3<bool>": `gl.uniform3iv(location, v);`,
  "vec4<bool>": `gl.uniform4iv(location, v);`
};

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/utils/generateUniformsSync.mjs
function generateUniformsSync(group, uniformData) {
  const funcFragments = [`
        var v = null;
        var cv = null;
        var cu = null;
        var t = 0;
        var gl = renderer.gl;
        var name = null;
    `];
  for (const i in group.uniforms) {
    if (!uniformData[i]) {
      if (group.uniforms[i] instanceof UniformGroup) {
        if (group.uniforms[i].ubo) {
          funcFragments.push(`
                        renderer.shader.bindUniformBlock(uv.${i}, "${i}");
                    `);
        } else {
          funcFragments.push(`
                        renderer.shader.updateUniformGroup(uv.${i});
                    `);
        }
      } else if (group.uniforms[i] instanceof BufferResource) {
        funcFragments.push(`
                        renderer.shader.bindBufferResource(uv.${i}, "${i}");
                    `);
      }
      continue;
    }
    const uniform = group.uniformStructures[i];
    let parsed = false;
    for (let j = 0; j < uniformParsers.length; j++) {
      const parser = uniformParsers[j];
      if (uniform.type === parser.type && parser.test(uniform)) {
        funcFragments.push(`name = "${i}";`, uniformParsers[j].uniform);
        parsed = true;
        break;
      }
    }
    if (!parsed) {
      const templateType = uniform.size === 1 ? UNIFORM_TO_SINGLE_SETTERS : UNIFORM_TO_ARRAY_SETTERS;
      const template = templateType[uniform.type].replace("location", `ud["${i}"].location`);
      funcFragments.push(`
            cu = ud["${i}"];
            cv = cu.value;
            v = uv["${i}"];
            ${template};`);
    }
  }
  return new Function("ud", "uv", "renderer", "syncData", funcFragments.join("\n"));
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/GlUniformGroupSystem.mjs
var GlUniformGroupSystem = class {
  /** @param renderer - The renderer this System works for. */
  constructor(renderer) {
    this._cache = {};
    this._uniformGroupSyncHash = {};
    this._renderer = renderer;
    this.gl = null;
    this._cache = {};
  }
  contextChange(gl) {
    this.gl = gl;
  }
  /**
   * Uploads the uniforms values to the currently bound shader.
   * @param group - the uniforms values that be applied to the current shader
   * @param program
   * @param syncData
   * @param syncData.textureCount
   */
  updateUniformGroup(group, program, syncData) {
    const programData = this._renderer.shader._getProgramData(program);
    if (!group.isStatic || group._dirtyId !== programData.uniformDirtyGroups[group.uid]) {
      programData.uniformDirtyGroups[group.uid] = group._dirtyId;
      const syncFunc = this._getUniformSyncFunction(group, program);
      syncFunc(programData.uniformData, group.uniforms, this._renderer, syncData);
    }
  }
  /**
   * Overridable by the pixi.js/unsafe-eval package to use static syncUniforms instead.
   * @param group
   * @param program
   */
  _getUniformSyncFunction(group, program) {
    return this._uniformGroupSyncHash[group._signature]?.[program._key] || this._createUniformSyncFunction(group, program);
  }
  _createUniformSyncFunction(group, program) {
    const uniformGroupSyncHash = this._uniformGroupSyncHash[group._signature] || (this._uniformGroupSyncHash[group._signature] = {});
    const id = this._getSignature(group, program._uniformData, "u");
    if (!this._cache[id]) {
      this._cache[id] = this._generateUniformsSync(group, program._uniformData);
    }
    uniformGroupSyncHash[program._key] = this._cache[id];
    return uniformGroupSyncHash[program._key];
  }
  _generateUniformsSync(group, uniformData) {
    return generateUniformsSync(group, uniformData);
  }
  /**
   * Takes a uniform group and data and generates a unique signature for them.
   * @param group - The uniform group to get signature of
   * @param group.uniforms
   * @param uniformData - Uniform information generated by the shader
   * @param preFix
   * @returns Unique signature of the uniform group
   */
  _getSignature(group, uniformData, preFix) {
    const uniforms = group.uniforms;
    const strings = [`${preFix}-`];
    for (const i in uniforms) {
      strings.push(i);
      if (uniformData[i]) {
        strings.push(uniformData[i].type);
      }
    }
    return strings.join("-");
  }
  /** Destroys this System and removes all its textures. */
  destroy() {
    this._renderer = null;
    this._cache = null;
  }
};
GlUniformGroupSystem.extension = {
  type: [
    ExtensionType.WebGLSystem
  ],
  name: "uniformGroup"
};

export {
  WGSL_TO_STD40_SIZE,
  createUboElementsSTD40,
  generateArraySyncSTD40,
  createUboSyncFunctionSTD40,
  GlUboSystem,
  TextureView,
  generateShaderSyncCode,
  IGLUniformData,
  GlProgramData,
  compileShader,
  defaultValue,
  mapType,
  mapGlToVertexFormat,
  extractAttributesFromGlProgram,
  getUboData,
  getUniformData,
  logProgramError,
  generateProgram,
  GlShaderSystem,
  UNIFORM_TO_SINGLE_SETTERS,
  UNIFORM_TO_ARRAY_SETTERS,
  generateUniformsSync,
  GlUniformGroupSystem
};
