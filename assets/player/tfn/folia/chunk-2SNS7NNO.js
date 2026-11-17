// Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; adapted for TuneFreeNext. See THIRD_PARTY_NOTICES.md and scripts/vendor_folia_skins.mjs.
import {
  GlobalResourceRegistry,
  ScreenSizeRegistry,
  UniformGroup,
  createIdFromString,
  deprecation,
  eventemitter3_default,
  getAttributeInfoFromFormat,
  isPow2,
  nextPow2,
  uid,
  v8_21_0,
  warn
} from "./chunk-NJ7XHR5M.js";

// scripts/folia/node_modules/pixi.js/lib/environment-browser/BrowserAdapter.mjs
var BrowserAdapter = {
  createCanvas: (width, height) => {
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    return canvas;
  },
  createImage: () => new Image(),
  getCanvasRenderingContext2D: () => CanvasRenderingContext2D,
  getWebGLRenderingContext: () => WebGLRenderingContext,
  getNavigator: () => navigator,
  getBaseUrl: () => document.baseURI ?? window.location.href,
  getFontFaceSet: () => document.fonts,
  fetch: (url, options) => fetch(url, options),
  parseXML: (xml) => {
    const parser = new DOMParser();
    return parser.parseFromString(xml, "text/xml");
  }
};

// scripts/folia/node_modules/pixi.js/lib/environment/adapter.mjs
var currentAdapter = BrowserAdapter;
var DOMAdapter = {
  /**
   * Returns the current adapter.
   * @returns {environment.Adapter} The current adapter.
   */
  get() {
    return currentAdapter;
  },
  /**
   * Sets the current adapter.
   * @param adapter - The new adapter.
   */
  set(adapter) {
    currentAdapter = adapter;
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/shared/texture/CanvasPool.mjs
var maxKeyDimension = 32767;
function bucketKey(width, height) {
  return (width << 17) + (height << 2);
}
var CanvasPoolClass = class {
  constructor(canvasOptions) {
    this._buckets = /* @__PURE__ */ new Map();
    this._screens = new ScreenSizeRegistry();
    this._enableFullScreen = false;
    this.canvasOptions = canvasOptions || {};
  }
  /**
   * Has no effect. The pool sizes canvases to the screens registered with
   * {@link CanvasPoolClass#setScreenSize|setScreenSize}.
   * @deprecated since 8.21.0
   */
  get enableFullScreen() {
    deprecation(v8_21_0, "CanvasPool.enableFullScreen is no longer used, the pool sizes canvases to the screens registered with setScreenSize.");
    return this._enableFullScreen;
  }
  set enableFullScreen(value) {
    deprecation(v8_21_0, "CanvasPool.enableFullScreen is no longer used, the pool sizes canvases to the screens registered with setScreenSize.");
    this._enableFullScreen = value;
  }
  /**
   * Creates texture with params that were specified in pool constructor.
   * @param pixelWidth - Width of texture in pixels.
   * @param pixelHeight - Height of texture in pixels.
   */
  _createCanvasAndContext(pixelWidth, pixelHeight) {
    const canvas = DOMAdapter.get().createCanvas();
    canvas.width = pixelWidth;
    canvas.height = pixelHeight;
    const context2 = canvas.getContext("2d");
    return { canvas, context: context2 };
  }
  /**
   * Gets a Power-of-Two canvas or screen sized canvas
   * @param minWidth - The minimum width of the canvas.
   * @param minHeight - The minimum height of the canvas.
   * @param resolution - The resolution of the canvas.
   * @returns The new canvas and its context.
   */
  getOptimalCanvasAndContext(minWidth, minHeight, resolution = 1) {
    const { width: canvasWidth, height: canvasHeight } = this.getOptimalSize(minWidth, minHeight, resolution);
    if (canvasWidth > maxKeyDimension || canvasHeight > maxKeyDimension) {
      warn(`CanvasPool: ${canvasWidth}x${canvasHeight} is larger than the ${maxKeyDimension}px pool key limit, canvases of this size may be pooled together`);
    }
    const key = bucketKey(canvasWidth, canvasHeight);
    let bucket = this._buckets.get(key);
    if (!bucket) {
      bucket = [];
      this._buckets.set(key, bucket);
    }
    let canvasAndContext = bucket.pop();
    if (!canvasAndContext) {
      canvasAndContext = this._createCanvasAndContext(canvasWidth, canvasHeight);
    }
    return canvasAndContext;
  }
  /**
   * The backing size, in physical pixels, that
   * {@link CanvasPoolClass#getOptimalCanvasAndContext|getOptimalCanvasAndContext} would allocate for a request,
   * without taking a canvas from the pool.
   *
   * Each axis is the next power of two, or the smallest registered screen the request fits inside
   * (see {@link CanvasPoolClass#setScreenSize|setScreenSize}).
   * @param minWidth - The minimum width of the canvas.
   * @param minHeight - The minimum height of the canvas.
   * @param resolution - The resolution of the canvas.
   * @returns The width and height the pooled canvas would have, in physical pixels.
   */
  getOptimalSize(minWidth, minHeight, resolution = 1) {
    const pixelWidth = Math.ceil(minWidth * resolution - 1e-6);
    const pixelHeight = Math.ceil(minHeight * resolution - 1e-6);
    const po2Width = nextPow2(pixelWidth);
    const screenWidth = this._screens.getFittingWidth(pixelWidth);
    const po2Height = nextPow2(pixelHeight);
    const screenHeight = this._screens.getFittingHeight(pixelHeight);
    return {
      width: screenWidth !== void 0 ? Math.min(screenWidth, po2Width) : po2Width,
      height: screenHeight !== void 0 ? Math.min(screenHeight, po2Height) : po2Height
    };
  }
  /**
   * Place a canvas back into the pool.
   * @param canvasAndContext
   */
  returnCanvasAndContext(canvasAndContext) {
    const canvas = canvasAndContext.canvas;
    const { width, height } = canvas;
    const canvases = this._buckets.get(bucketKey(width, height));
    if (!canvases) return;
    canvasAndContext.context.resetTransform();
    canvasAndContext.context.clearRect(0, 0, width, height);
    canvases.push(canvasAndContext);
  }
  /**
   * Registers the screen size of a renderer with the pool, in physical pixels.
   *
   * While a screen is registered, a request that fits inside it on an axis is given that screen's size on
   * that axis instead of the next power of two, which stops a full screen canvas from being allocated far
   * larger than the screen. Requests larger than every registered screen on an axis keep the power of two
   * size - the pool never rounds a request up to a screen it does not fit in.
   * @param rendererUid - The uid of the renderer, used to update or remove this screen later.
   * @param pixelWidth - The width of the screen in physical pixels.
   * @param pixelHeight - The height of the screen in physical pixels.
   */
  setScreenSize(rendererUid, pixelWidth, pixelHeight) {
    if (!this._screens.set(rendererUid, pixelWidth, pixelHeight)) return;
    this._pruneScreenCanvases();
  }
  /**
   * Removes a screen previously registered with
   * {@link CanvasPoolClass#setScreenSize|setScreenSize}, dropping any idle canvases that were
   * only being kept for it.
   * @param rendererUid - The uid the screen was registered with.
   */
  removeScreen(rendererUid) {
    if (!this._screens.remove(rendererUid)) return;
    this._pruneScreenCanvases();
  }
  /** Clears the pool. */
  clear() {
    this._buckets.clear();
  }
  /**
   * Drops the idle canvases in every bucket that has a non power of two dimension matching no live
   * screen. Power of two buckets are always kept, as any request can fall back to them.
   */
  _pruneScreenCanvases() {
    for (const [key] of this._buckets) {
      const width = key >>> 17;
      const height = key >>> 2 & 32767;
      if ((isPow2(width) || this._screens.hasWidth(width)) && (isPow2(height) || this._screens.hasHeight(height))) continue;
      this._buckets.delete(key);
    }
  }
};
var CanvasPool = new CanvasPoolClass();
GlobalResourceRegistry.register(CanvasPool);

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/getTestContext.mjs
var context;
function getTestContext() {
  if (!context || context?.isContextLost()) {
    const canvas = DOMAdapter.get().createCanvas();
    context = canvas.getContext("webgl", {});
  }
  return context;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/getMaxFragmentPrecision.mjs
var maxFragmentPrecision;
function getMaxFragmentPrecision() {
  if (!maxFragmentPrecision) {
    maxFragmentPrecision = "mediump";
    const gl = getTestContext();
    if (gl) {
      if (gl.getShaderPrecisionFormat) {
        const shaderFragment = gl.getShaderPrecisionFormat(gl.FRAGMENT_SHADER, gl.HIGH_FLOAT);
        maxFragmentPrecision = shaderFragment.precision ? "highp" : "mediump";
      }
    }
  }
  return maxFragmentPrecision;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/preprocessors/addProgramDefines.mjs
function addProgramDefines(src, isES300, isFragment) {
  if (isES300) return src;
  if (isFragment) {
    src = src.replace("out vec4 finalColor;", "");
    return `

        #ifdef GL_ES // This checks if it is WebGL1
        #define in varying
        #define finalColor gl_FragColor
        #define texture texture2D
        #endif
        ${src}
        `;
  }
  return `

        #ifdef GL_ES // This checks if it is WebGL1
        #define in attribute
        #define out varying
        #endif
        ${src}
        `;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/preprocessors/ensurePrecision.mjs
function ensurePrecision(src, options, isFragment) {
  const maxSupportedPrecision = isFragment ? options.maxSupportedFragmentPrecision : options.maxSupportedVertexPrecision;
  if (src.substring(0, 9) !== "precision") {
    let precision = isFragment ? options.requestedFragmentPrecision : options.requestedVertexPrecision;
    if (precision === "highp" && maxSupportedPrecision !== "highp") {
      precision = "mediump";
    }
    return `precision ${precision} float;
${src}`;
  } else if (maxSupportedPrecision !== "highp" && src.substring(0, 15) === "precision highp") {
    return src.replace("precision highp", "precision mediump");
  }
  return src;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/preprocessors/insertVersion.mjs
function insertVersion(src, isES300) {
  if (!isES300) return src;
  return `#version 300 es
${src}`;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/preprocessors/setProgramName.mjs
var fragmentNameCache = {};
var VertexNameCache = {};
function setProgramName(src, { name = `pixi-program` }, isFragment = true) {
  name = name.replace(/\s+/g, "-");
  name += isFragment ? "-fragment" : "-vertex";
  const nameCache = isFragment ? fragmentNameCache : VertexNameCache;
  if (nameCache[name]) {
    nameCache[name]++;
    name += `-${nameCache[name]}`;
  } else {
    nameCache[name] = 1;
  }
  if (src.indexOf("#define SHADER_NAME") !== -1) return src;
  const shaderName = `#define SHADER_NAME ${name}`;
  return `${shaderName}
${src}`;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/program/preprocessors/stripVersion.mjs
function stripVersion(src, isES300) {
  if (!isES300) return src;
  return src.replace("#version 300 es", "");
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/shader/GlProgram.mjs
var processes = {
  // strips any version headers..
  stripVersion,
  // adds precision string if not already present
  ensurePrecision,
  // add some defines if WebGL1 to make it more compatible with WebGL2 shaders
  addProgramDefines,
  // add the program name to the shader
  setProgramName,
  // add the version string to the shader header
  insertVersion
};
var programCache = /* @__PURE__ */ Object.create(null);
var _GlProgram = class _GlProgram2 {
  /**
   * Creates a shiny new GlProgram. Used by WebGL renderer.
   * @param options - The options for the program.
   */
  constructor(options) {
    options = { ..._GlProgram2.defaultOptions, ...options };
    const isES300 = options.fragment.indexOf("#version 300 es") !== -1;
    const preprocessorOptions = {
      stripVersion: isES300,
      ensurePrecision: {
        requestedFragmentPrecision: options.preferredFragmentPrecision,
        requestedVertexPrecision: options.preferredVertexPrecision,
        maxSupportedVertexPrecision: "highp",
        maxSupportedFragmentPrecision: getMaxFragmentPrecision()
      },
      setProgramName: {
        name: options.name
      },
      addProgramDefines: isES300,
      insertVersion: isES300
    };
    let fragment = options.fragment;
    let vertex = options.vertex;
    Object.keys(processes).forEach((processKey) => {
      const processOptions = preprocessorOptions[processKey];
      fragment = processes[processKey](fragment, processOptions, true);
      vertex = processes[processKey](vertex, processOptions, false);
    });
    this.fragment = fragment;
    this.vertex = vertex;
    this.transformFeedbackVaryings = options.transformFeedbackVaryings;
    this._key = createIdFromString(`${this.vertex}:${this.fragment}`, "gl-program");
  }
  /** destroys the program */
  destroy() {
    this.fragment = null;
    this.vertex = null;
    this._attributeData = null;
    this._uniformData = null;
    this._uniformBlockData = null;
    this.transformFeedbackVaryings = null;
    programCache[this._cacheKey] = null;
  }
  /**
   * Helper function that creates a program for a given source.
   * It will check the program cache if the program has already been created.
   * If it has that one will be returned, if not a new one will be created and cached.
   * @param options - The options for the program.
   * @returns A program using the same source
   */
  static from(options) {
    const key = `${options.vertex}:${options.fragment}`;
    if (!programCache[key]) {
      programCache[key] = new _GlProgram2(options);
      programCache[key]._cacheKey = key;
    }
    return programCache[key];
  }
};
_GlProgram.defaultOptions = {
  preferredVertexPrecision: "highp",
  preferredFragmentPrecision: "mediump"
};
var GlProgram = _GlProgram;

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gpu/shader/utils/extractAttributesFromGpuProgram.mjs
var WGSL_TO_VERTEX_TYPES = {
  f32: "float32",
  "vec2<f32>": "float32x2",
  "vec3<f32>": "float32x3",
  "vec4<f32>": "float32x4",
  vec2f: "float32x2",
  vec3f: "float32x3",
  vec4f: "float32x4",
  i32: "sint32",
  "vec2<i32>": "sint32x2",
  "vec3<i32>": "sint32x3",
  "vec4<i32>": "sint32x4",
  vec2i: "sint32x2",
  vec3i: "sint32x3",
  vec4i: "sint32x4",
  u32: "uint32",
  "vec2<u32>": "uint32x2",
  "vec3<u32>": "uint32x3",
  "vec4<u32>": "uint32x4",
  vec2u: "uint32x2",
  vec3u: "uint32x3",
  vec4u: "uint32x4",
  bool: "uint32",
  "vec2<bool>": "uint32x2",
  "vec3<bool>": "uint32x3",
  "vec4<bool>": "uint32x4"
};
var LOCATION_REGEX = /@location\((\d+)\)\s+([a-zA-Z0-9_]+)\s*:\s*([a-zA-Z0-9_<>]+)(?:,|\s|\)|$)/g;
function parseLocations(str, results) {
  let match;
  while ((match = LOCATION_REGEX.exec(str)) !== null) {
    const format = WGSL_TO_VERTEX_TYPES[match[3]] ?? "float32";
    results[match[2]] = {
      location: parseInt(match[1], 10),
      format,
      stride: getAttributeInfoFromFormat(format).stride,
      offset: 0,
      instance: false,
      start: 0
    };
  }
  LOCATION_REGEX.lastIndex = 0;
}
function stripComments(source) {
  return source.replace(/\/\/.*$/gm, "").replace(/\/\*[\s\S]*?\*\//g, "");
}
function extractAttributesFromGpuProgram({ source, entryPoint }) {
  const results = {};
  const cleanSource = stripComments(source);
  const mainVertStart = cleanSource.indexOf(`fn ${entryPoint}(`);
  if (mainVertStart === -1) {
    return results;
  }
  const arrowFunctionStart = cleanSource.indexOf("->", mainVertStart);
  if (arrowFunctionStart === -1) {
    return results;
  }
  const functionArgsSubstring = cleanSource.substring(mainVertStart, arrowFunctionStart);
  parseLocations(functionArgsSubstring, results);
  if (Object.keys(results).length === 0) {
    const structMatch = functionArgsSubstring.match(/\(\s*\w+\s*:\s*(\w+)/);
    if (structMatch) {
      const structName = structMatch[1];
      const structRegex = new RegExp(`struct\\s+${structName}\\s*\\{([^}]+)\\}`, "s");
      const structBody = cleanSource.match(structRegex);
      if (structBody) {
        parseLocations(structBody[1], results);
      }
    }
  }
  return results;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gpu/shader/utils/extractStructAndGroups.mjs
function extractStructAndGroups(wgsl) {
  const linePattern = /(^|[^/])@(group|binding)\(\d+\)[^;]+;/g;
  const groupPattern = /@group\((\d+)\)/;
  const bindingPattern = /@binding\((\d+)\)/;
  const namePattern = /var(<[^>]+>)? (\w+)/;
  const typePattern = /:\s*([\w<>]+)/;
  const structPattern = /struct\s+(\w+)\s*{([^}]+)}/g;
  const structMemberPattern = /(\w+)\s*:\s*([\w\<\>]+)/g;
  const structName = /struct\s+(\w+)/;
  const groups = wgsl.match(linePattern)?.map((item) => {
    const varMatch = item.match(namePattern);
    const varQualifier = varMatch?.[1] ?? "";
    let accessMode;
    if (varQualifier === "<uniform>") {
      accessMode = "uniform";
    } else if (varQualifier.startsWith("<storage")) {
      accessMode = "storage";
    }
    return {
      group: parseInt(item.match(groupPattern)[1], 10),
      binding: parseInt(item.match(bindingPattern)[1], 10),
      name: varMatch[2],
      accessMode,
      type: item.match(typePattern)[1]
    };
  });
  if (!groups) {
    return {
      groups: [],
      structs: []
    };
  }
  const structs = wgsl.match(structPattern)?.map((struct) => {
    const name = struct.match(structName)[1];
    const members = struct.match(structMemberPattern).reduce((acc, member) => {
      const [name2, type] = member.split(":");
      acc[name2.trim()] = type.trim();
      return acc;
    }, {});
    if (!members) {
      return null;
    }
    return { name, members };
  }).filter(({ name }) => groups.some(
    (group) => (
      // Handle both direct type matches and generic types like array<StructName>
      group.type === name || group.type.includes(`<${name}>`)
    )
  )) ?? [];
  return {
    groups,
    structs
  };
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/shared/shader/const.mjs
var ShaderStage = /* @__PURE__ */ ((ShaderStage2) => {
  ShaderStage2[ShaderStage2["VERTEX"] = 1] = "VERTEX";
  ShaderStage2[ShaderStage2["FRAGMENT"] = 2] = "FRAGMENT";
  ShaderStage2[ShaderStage2["COMPUTE"] = 4] = "COMPUTE";
  return ShaderStage2;
})(ShaderStage || {});

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gpu/shader/utils/generateGpuLayoutGroups.mjs
function generateGpuLayoutGroups({ groups }) {
  const layout = [];
  for (let i = 0; i < groups.length; i++) {
    const group = groups[i];
    if (!layout[group.group]) {
      layout[group.group] = [];
    }
    if (group.accessMode === "uniform") {
      layout[group.group].push({
        binding: group.binding,
        visibility: ShaderStage.VERTEX | ShaderStage.FRAGMENT,
        buffer: {
          type: "uniform"
        }
      });
    } else if (group.accessMode === "storage") {
      layout[group.group].push({
        binding: group.binding,
        visibility: ShaderStage.VERTEX | ShaderStage.FRAGMENT,
        buffer: {
          type: "read-only-storage"
        }
      });
    } else if (group.type === "sampler") {
      layout[group.group].push({
        binding: group.binding,
        visibility: ShaderStage.VERTEX | ShaderStage.FRAGMENT,
        sampler: {
          type: "filtering"
        }
      });
    } else if (group.type === "sampler_comparison") {
      layout[group.group].push({
        binding: group.binding,
        visibility: ShaderStage.VERTEX | ShaderStage.FRAGMENT,
        sampler: {
          type: "comparison"
        }
      });
    } else if (group.type === "texture_2d" || group.type.startsWith("texture_2d<")) {
      layout[group.group].push({
        binding: group.binding,
        visibility: ShaderStage.VERTEX | ShaderStage.FRAGMENT,
        texture: {
          sampleType: "float",
          viewDimension: "2d",
          multisampled: false
        }
      });
    } else if (group.type === "texture_depth_2d") {
      layout[group.group].push({
        binding: group.binding,
        visibility: ShaderStage.VERTEX | ShaderStage.FRAGMENT,
        texture: {
          sampleType: "depth",
          viewDimension: "2d",
          multisampled: false
        }
      });
    } else if (group.type === "texture_depth_2d_array") {
      layout[group.group].push({
        binding: group.binding,
        visibility: ShaderStage.VERTEX | ShaderStage.FRAGMENT,
        texture: {
          sampleType: "depth",
          viewDimension: "2d-array",
          multisampled: false
        }
      });
    } else if (group.type === "texture_2d_array" || group.type.startsWith("texture_2d_array<")) {
      layout[group.group].push({
        binding: group.binding,
        visibility: ShaderStage.VERTEX | ShaderStage.FRAGMENT,
        texture: {
          sampleType: "float",
          viewDimension: "2d-array",
          multisampled: false
        }
      });
    } else if (group.type === "texture_cube" || group.type.startsWith("texture_cube<")) {
      layout[group.group].push({
        binding: group.binding,
        visibility: ShaderStage.VERTEX | ShaderStage.FRAGMENT,
        texture: {
          sampleType: "float",
          viewDimension: "cube",
          multisampled: false
        }
      });
    }
  }
  for (let i = 0; i < layout.length; i++) {
    layout[i] || (layout[i] = []);
  }
  return layout;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gpu/shader/utils/generateLayoutHash.mjs
function generateLayoutHash({ groups }) {
  const layout = [];
  for (let i = 0; i < groups.length; i++) {
    const group = groups[i];
    if (!layout[group.group]) {
      layout[group.group] = {};
    }
    layout[group.group][group.name] = group.binding;
  }
  return layout;
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gpu/shader/utils/removeStructAndGroupDuplicates.mjs
function removeStructAndGroupDuplicates(vertexStructsAndGroups, fragmentStructsAndGroups) {
  const structNameSet = /* @__PURE__ */ new Set();
  const dupeGroupKeySet = /* @__PURE__ */ new Set();
  const structs = [...vertexStructsAndGroups.structs, ...fragmentStructsAndGroups.structs].filter((struct) => {
    if (structNameSet.has(struct.name)) {
      return false;
    }
    structNameSet.add(struct.name);
    return true;
  });
  const groups = [...vertexStructsAndGroups.groups, ...fragmentStructsAndGroups.groups].filter((group) => {
    const key = `${group.name}-${group.binding}`;
    if (dupeGroupKeySet.has(key)) {
      return false;
    }
    dupeGroupKeySet.add(key);
    return true;
  });
  return { structs, groups };
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gpu/shader/GpuProgram.mjs
var programCache2 = /* @__PURE__ */ Object.create(null);
var GpuProgram = class _GpuProgram {
  /**
   * Create a new GpuProgram
   * @param options - The options for the gpu program
   */
  constructor(options) {
    this._layoutKey = 0;
    this._attributeLocationsKey = 0;
    const { fragment, vertex, layout, gpuLayout, name } = options;
    this.name = name;
    this.fragment = fragment;
    this.vertex = vertex;
    if (fragment.source === vertex.source) {
      const structsAndGroups = extractStructAndGroups(fragment.source);
      this.structsAndGroups = structsAndGroups;
    } else {
      const vertexStructsAndGroups = extractStructAndGroups(vertex.source);
      const fragmentStructsAndGroups = extractStructAndGroups(fragment.source);
      this.structsAndGroups = removeStructAndGroupDuplicates(vertexStructsAndGroups, fragmentStructsAndGroups);
    }
    this.layout = layout ?? generateLayoutHash(this.structsAndGroups);
    this.gpuLayout = gpuLayout ?? generateGpuLayoutGroups(this.structsAndGroups);
    this.autoAssignGlobalUniforms = !!(this.layout[0]?.globalUniforms !== void 0);
    this.autoAssignLocalUniforms = !!(this.layout[1]?.localUniforms !== void 0);
    this._generateProgramKey();
  }
  // TODO maker this pure
  _generateProgramKey() {
    const { vertex, fragment } = this;
    const bigKey = vertex.source + fragment.source + vertex.entryPoint + fragment.entryPoint;
    this._layoutKey = createIdFromString(bigKey, "program");
  }
  get attributeData() {
    this._attributeData ?? (this._attributeData = extractAttributesFromGpuProgram(this.vertex));
    return this._attributeData;
  }
  /** destroys the program */
  destroy() {
    this.gpuLayout = null;
    this.layout = null;
    this.structsAndGroups = null;
    this.fragment = null;
    this.vertex = null;
    programCache2[this._cacheKey] = null;
  }
  /**
   * Helper function that creates a program for a given source.
   * It will check the program cache if the program has already been created.
   * If it has that one will be returned, if not a new one will be created and cached.
   * @param options - The options for the program.
   * @returns A program using the same source
   */
  static from(options) {
    const key = `${options.vertex.source}:${options.fragment.source}:${options.fragment.entryPoint}:${options.vertex.entryPoint}`;
    if (!programCache2[key]) {
      programCache2[key] = new _GpuProgram(options);
      programCache2[key]._cacheKey = key;
    }
    return programCache2[key];
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gpu/shader/BindGroup.mjs
var BindGroup = class {
  /**
   * Create a new instance of the Bind Group.
   * @param resources - The resources that are bound together for use by a shader.
   */
  constructor(resources) {
    this.resources = /* @__PURE__ */ Object.create(null);
    this._dirty = true;
    let index = 0;
    for (const i in resources) {
      const resource = resources[i];
      this.setResource(resource, index++);
    }
  }
  /**
   * A key used internally to match it up to a WebGPU BindGroup.
   * Lazily rebuilt from resource IDs when dirty.
   * @internal
   */
  get _key() {
    if (this._dirty) {
      this._dirty = false;
      const keyParts = [];
      let index = 0;
      for (const i in this.resources) {
        keyParts[index++] = this.resources[i] ? this.resources[i]._resourceId : -1;
      }
      this._keyValue = keyParts.join("|");
    }
    return this._keyValue;
  }
  /**
   * Set a resource at a given index. This function will
   * ensure that listeners will be removed from the current resource
   * and added to the new resource.
   * @param resource - The resource to set.
   * @param index - The index to set the resource at.
   */
  setResource(resource, index) {
    const currentResource = this.resources[index];
    if (resource === currentResource) return;
    if (currentResource) {
      currentResource.off?.("change", this.onResourceChange, this);
    }
    resource.on?.("change", this.onResourceChange, this);
    this.resources[index] = resource;
    this._dirty = true;
  }
  /**
   * Returns the resource at the current specified index.
   * @param index - The index of the resource to get.
   * @returns - The resource at the specified index.
   */
  getResource(index) {
    return this.resources[index];
  }
  /**
   * Used internally to 'touch' each resource, to ensure that the GC
   * knows that all resources in this bind group are still being used.
   * @param now - The current time in milliseconds.
   * @internal
   */
  _touch(now) {
    const resources = this.resources;
    for (const i in resources) {
      const resource = resources[i];
      if (!resource) continue;
      resource._gcLastUsed = now;
    }
  }
  /** Destroys this bind group and removes all listeners. */
  destroy() {
    const resources = this.resources;
    for (const i in resources) {
      const resource = resources[i];
      resource?.off?.("change", this.onResourceChange, this);
    }
    this.resources = null;
  }
  onResourceChange(resource) {
    this._dirty = true;
    if (resource.destroyed) {
      const resources = this.resources;
      for (const i in resources) {
        if (resources[i] === resource) {
          resources[i] = null;
        }
      }
      warn(`[BindGroup] a '${resource._resourceType}' was destroyed while still bound to a shader. Remove it from the shader before destroying it.`);
    }
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/types.mjs
var RendererType = /* @__PURE__ */ ((RendererType2) => {
  RendererType2[RendererType2["WEBGL"] = 1] = "WEBGL";
  RendererType2[RendererType2["WEBGPU"] = 2] = "WEBGPU";
  RendererType2[RendererType2["CANVAS"] = 4] = "CANVAS";
  RendererType2[RendererType2["BOTH"] = 3] = "BOTH";
  return RendererType2;
})(RendererType || {});

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/shared/shader/ShaderOverrides.mjs
var ShaderOverrides = class _ShaderOverrides {
  /**
   * @param data - A dictionary of constants to set on the shader.
   * Keys should match the constant names in the WGSL shader.
   */
  constructor(data) {
    this.data = { ...data };
    const key = Object.keys(data).sort().map((k) => `${k}:${data[k]}`).join("|");
    this.id = createIdFromString(key, "shader-overrides");
  }
  /**
   * Creates a ShaderOverrides instance from a plain object or existing instance.
   * @param overrides - The overrides to convert.
   * @returns A ShaderOverrides instance.
   */
  static from(overrides) {
    if (overrides instanceof _ShaderOverrides) {
      return overrides;
    }
    return new _ShaderOverrides(overrides);
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/shared/shader/Shader.mjs
var Shader = class _Shader extends eventemitter3_default {
  constructor(options) {
    super();
    this.uid = uid("shader");
    this._uniformBindMap = /* @__PURE__ */ Object.create(null);
    this._ownedBindGroups = [];
    this._destroyed = false;
    let {
      gpuProgram,
      glProgram,
      groups,
      resources,
      compatibleRenderers,
      groupMap,
      overrides
    } = options;
    this._overrides = overrides ? ShaderOverrides.from(overrides) : null;
    this.gpuProgram = gpuProgram;
    this.glProgram = glProgram;
    if (compatibleRenderers === void 0) {
      compatibleRenderers = 0;
      if (gpuProgram) compatibleRenderers |= RendererType.WEBGPU;
      if (glProgram) compatibleRenderers |= RendererType.WEBGL;
    }
    this.compatibleRenderers = compatibleRenderers;
    const nameHash = {};
    if (groupMap) {
      for (const i in groupMap) {
        for (const j in groupMap[i]) {
          const uniformName = groupMap[i][j];
          nameHash[uniformName] = {
            group: i,
            binding: j,
            name: uniformName
          };
        }
      }
    }
    if (!resources && !groups) {
      resources = {};
    }
    if (resources && groups) {
      throw new Error("[Shader] Cannot have both resources and groups");
    } else if (!gpuProgram && groups && !groupMap) {
      throw new Error("[Shader] No group map or WebGPU shader provided - consider using resources instead.");
    } else if (gpuProgram && groups && !groupMap) {
      const groupData = gpuProgram.structsAndGroups.groups;
      groupMap = {};
      groupData.forEach((data) => {
        groupMap[data.group] = groupMap[data.group] || {};
        groupMap[data.group][data.binding] = data.name;
        nameHash[data.name] = data;
      });
    } else if (resources) {
      groups = {};
      groupMap || (groupMap = {});
      if (gpuProgram) {
        const groupData = gpuProgram.structsAndGroups.groups;
        groupData.forEach((data) => {
          groupMap[data.group] = groupMap[data.group] || {};
          groupMap[data.group][data.binding] = data.name;
          nameHash[data.name] = data;
        });
      }
      let bindTick = 0;
      for (const i in resources) {
        if (nameHash[i]) continue;
        if (gpuProgram && !glProgram) {
          warn(`[Shader] the resource '${i}' matches no binding in the WGSL source \u2014 is the name correct?`);
        }
        if (!groups[99]) {
          groups[99] = new BindGroup();
          this._ownedBindGroups.push(groups[99]);
        }
        nameHash[i] = { group: 99, binding: bindTick, name: i };
        groupMap[99] = groupMap[99] || {};
        groupMap[99][bindTick] = i;
        bindTick++;
      }
      for (const i in resources) {
        const name = i;
        let value = resources[i];
        if (!value.source && !value._resourceType) {
          value = new UniformGroup(value);
        }
        const data = nameHash[name];
        if (data) {
          if (!groups[data.group]) {
            groups[data.group] = new BindGroup();
            this._ownedBindGroups.push(groups[data.group]);
          }
          groups[data.group].setResource(value, data.binding);
        }
      }
    }
    this.groups = groups;
    this._uniformBindMap = groupMap;
    this.resources = this._buildResourceAccessor(groups, nameHash);
  }
  /**
   * Sometimes a resource group will be provided later (for example global uniforms)
   * In such cases, this method can be used to let the shader know about the group.
   * @param name - the name of the resource group
   * @param groupIndex - the index of the group (should match the webGPU shader group location)
   * @param bindIndex - the index of the bind point (should match the webGPU shader bind point)
   */
  addResource(name, groupIndex, bindIndex) {
    var _a, _b;
    (_a = this._uniformBindMap)[groupIndex] || (_a[groupIndex] = {});
    (_b = this._uniformBindMap[groupIndex])[bindIndex] || (_b[bindIndex] = name);
    if (!this.groups[groupIndex]) {
      this.groups[groupIndex] = new BindGroup();
      this._ownedBindGroups.push(this.groups[groupIndex]);
    }
  }
  _buildResourceAccessor(groups, nameHash) {
    const uniformsOut = {};
    for (const i in nameHash) {
      const data = nameHash[i];
      Object.defineProperty(uniformsOut, data.name, {
        get() {
          return groups[data.group].getResource(data.binding);
        },
        set(value) {
          groups[data.group].setResource(value, data.binding);
        }
      });
    }
    return uniformsOut;
  }
  /**
   * Use to destroy the shader when its not longer needed.
   * It will destroy the resources and remove listeners.
   * @param destroyPrograms - if the programs should be destroyed as well.
   * Make sure its not being used by other shaders!
   */
  destroy(destroyPrograms = false) {
    if (this._destroyed) return;
    this._destroyed = true;
    this.emit("destroy", this);
    if (destroyPrograms) {
      this.gpuProgram?.destroy();
      this.glProgram?.destroy();
    }
    this.gpuProgram = null;
    this.glProgram = null;
    this.removeAllListeners();
    this._uniformBindMap = null;
    this._ownedBindGroups.forEach((bindGroup) => {
      bindGroup.destroy();
    });
    this._ownedBindGroups = null;
    this.resources = null;
    this.groups = null;
    this._overrides = null;
  }
  static from(options) {
    const { gpu, gl, ...rest } = options;
    let gpuProgram;
    let glProgram;
    if (gpu) {
      gpuProgram = GpuProgram.from(gpu);
    }
    if (gl) {
      glProgram = GlProgram.from(gl);
    }
    return new _Shader({
      gpuProgram,
      glProgram,
      ...rest
    });
  }
};

export {
  BrowserAdapter,
  DOMAdapter,
  CanvasPoolClass,
  CanvasPool,
  getTestContext,
  getMaxFragmentPrecision,
  addProgramDefines,
  ensurePrecision,
  insertVersion,
  setProgramName,
  stripVersion,
  GlProgram,
  extractAttributesFromGpuProgram,
  extractStructAndGroups,
  ShaderStage,
  generateGpuLayoutGroups,
  generateLayoutHash,
  removeStructAndGroupDuplicates,
  GpuProgram,
  BindGroup,
  RendererType,
  ShaderOverrides,
  Shader
};
