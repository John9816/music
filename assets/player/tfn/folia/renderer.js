// Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; adapted for TuneFreeNext. See THIRD_PARTY_NOTICES.md and scripts/vendor_folia_skins.mjs.
import {
  ParticleBuffer
} from "./chunk-TXEEYGFO.js";
import {
  GpuUboSystem,
  WGSL_ALIGN_SIZE_DATA
} from "./chunk-43EOV44U.js";
import {
  GlShaderSystem,
  GlUboSystem,
  GlUniformGroupSystem,
  TextureView,
  WGSL_TO_STD40_SIZE
} from "./chunk-YSJYTLS5.js";
import {
  BufferResource,
  UboSystem,
  uniformParsers
} from "./chunk-I4JNEM5R.js";
import {
  AbstractRenderer
} from "./chunk-OMWRG7ZI.js";
import "./chunk-RMIIME3Z.js";
import "./chunk-LXMKFHNO.js";
import {
  TextureSource,
  TextureStyle,
  UniformGroup,
  getAttributeInfoFromFormat
} from "./chunk-NJ7XHR5M.js";

// scripts/folia/node_modules/pixi.js/lib/unsafe-eval/particle/particleUpdateFunctions.mjs
var particleUpdateFunctions = {
  aVertex: (ps, f32v, _u32v, offset, stride) => {
    let w0 = 0;
    let w1 = 0;
    let h0 = 0;
    let h1 = 0;
    for (let i = 0; i < ps.length; ++i) {
      const p = ps[i];
      const texture = p.texture;
      const sx = p.scaleX;
      const sy = p.scaleY;
      const ax = p.anchorX;
      const ay = p.anchorY;
      const trim = texture.trim;
      const orig = texture.orig;
      if (trim) {
        w1 = trim.x - ax * orig.width;
        w0 = w1 + trim.width;
        h1 = trim.y - ay * orig.height;
        h0 = h1 + trim.height;
      } else {
        w0 = orig.width * (1 - ax);
        w1 = orig.width * -ax;
        h0 = orig.height * (1 - ay);
        h1 = orig.height * -ay;
      }
      f32v[offset] = w1 * sx;
      f32v[offset + 1] = h1 * sy;
      f32v[offset + stride] = w0 * sx;
      f32v[offset + stride + 1] = h1 * sy;
      f32v[offset + stride * 2] = w0 * sx;
      f32v[offset + stride * 2 + 1] = h0 * sy;
      f32v[offset + stride * 3] = w1 * sx;
      f32v[offset + stride * 3 + 1] = h0 * sy;
      offset += stride * 4;
    }
  },
  aPosition: (ps, f32v, _u32v, offset, stride) => {
    for (let i = 0; i < ps.length; ++i) {
      const p = ps[i];
      const x = p.x;
      const y = p.y;
      f32v[offset] = x;
      f32v[offset + 1] = y;
      f32v[offset + stride] = x;
      f32v[offset + stride + 1] = y;
      f32v[offset + stride * 2] = x;
      f32v[offset + stride * 2 + 1] = y;
      f32v[offset + stride * 3] = x;
      f32v[offset + stride * 3 + 1] = y;
      offset += stride * 4;
    }
  },
  aRotation: (ps, f32v, _u32v, offset, stride) => {
    for (let i = 0; i < ps.length; ++i) {
      const rotation = ps[i].rotation;
      f32v[offset] = rotation;
      f32v[offset + stride] = rotation;
      f32v[offset + stride * 2] = rotation;
      f32v[offset + stride * 3] = rotation;
      offset += stride * 4;
    }
  },
  aUV: (ps, f32v, _u32v, offset, stride) => {
    for (let i = 0; i < ps.length; ++i) {
      const uvs = ps[i].texture.uvs;
      f32v[offset] = uvs.x0;
      f32v[offset + 1] = uvs.y0;
      f32v[offset + stride] = uvs.x1;
      f32v[offset + stride + 1] = uvs.y1;
      f32v[offset + stride * 2] = uvs.x2;
      f32v[offset + stride * 2 + 1] = uvs.y2;
      f32v[offset + stride * 3] = uvs.x3;
      f32v[offset + stride * 3 + 1] = uvs.y3;
      offset += stride * 4;
    }
  },
  aColor: (ps, _f32v, u32v, offset, stride) => {
    for (let i = 0; i < ps.length; ++i) {
      const c = ps[i].color;
      u32v[offset] = c;
      u32v[offset + stride] = c;
      u32v[offset + stride * 2] = c;
      u32v[offset + stride * 3] = c;
      offset += stride * 4;
    }
  }
};

// scripts/folia/node_modules/pixi.js/lib/unsafe-eval/particle/generateParticleUpdatePolyfill.mjs
function generateParticleUpdatePolyfill(properties) {
  const allProperties = Object.values(properties);
  const dynamicProperties = allProperties.filter((p) => p.dynamic);
  const staticProperties = allProperties.filter((p) => !p.dynamic);
  return {
    dynamicUpdate: generateUpdateFunction(dynamicProperties),
    staticUpdate: generateUpdateFunction(staticProperties)
  };
}
function generateUpdateFunction(properties) {
  let stride = 0;
  const updateData = [];
  for (let i = 0; i < properties.length; i++) {
    const property = properties[i];
    const attributeStride = getAttributeInfoFromFormat(property.format).stride / 4;
    stride += attributeStride;
    updateData.push({
      stride: attributeStride,
      updateFunction: property.updateFunction || particleUpdateFunctions[property.attributeName]
    });
  }
  return (ps, f32v, u32v) => {
    let offset = 0;
    for (let i = 0; i < updateData.length; i++) {
      const obx = updateData[i];
      obx.updateFunction(ps, f32v, u32v, offset, stride);
      offset += obx.stride;
    }
  };
}

// scripts/folia/node_modules/pixi.js/lib/unsafe-eval/shader/generateShaderSyncPolyfill.mjs
function generateShaderSyncPolyfill() {
  return syncShader;
}
function syncShader(renderer, shader, syncData) {
  const gl = renderer.gl;
  const shaderSystem = renderer.shader;
  const programData = shaderSystem._getProgramData(shader.glProgram);
  for (const i in shader.groups) {
    const bindGroup = shader.groups[i];
    for (const j in bindGroup.resources) {
      const resource = bindGroup.resources[j];
      if (resource instanceof UniformGroup) {
        if (resource.ubo) {
          shaderSystem.bindUniformBlock(
            resource,
            shader._uniformBindMap[i][j],
            syncData.blockIndex++
          );
        } else {
          shaderSystem.updateUniformGroup(resource);
        }
      } else if (resource instanceof BufferResource) {
        shaderSystem.bindUniformBlock(
          resource,
          shader._uniformBindMap[i][j],
          syncData.blockIndex++
        );
      } else if (resource instanceof TextureSource || resource instanceof TextureView) {
        renderer.texture.bind(resource, syncData.textureCount);
        const uniformName = shader._uniformBindMap[i][j];
        const uniformData = programData.uniformData[uniformName];
        if (uniformData) {
          if (uniformData.value !== syncData.textureCount) {
            gl.uniform1i(uniformData.location, syncData.textureCount);
          }
          syncData.textureCount++;
        }
      } else if (resource instanceof TextureStyle) {
      }
    }
  }
}

// scripts/folia/node_modules/pixi.js/lib/unsafe-eval/ubo/uboSyncFunctions.mjs
var uboParserFunctions = [
  (name, data, offset, uv, _v) => {
    const matrix = uv[name].toArray(true);
    data[offset] = matrix[0];
    data[offset + 1] = matrix[1];
    data[offset + 2] = matrix[2];
    data[offset + 4] = matrix[3];
    data[offset + 5] = matrix[4];
    data[offset + 6] = matrix[5];
    data[offset + 8] = matrix[6];
    data[offset + 9] = matrix[7];
    data[offset + 10] = matrix[8];
  },
  (name, data, offset, uv, v) => {
    v = uv[name];
    data[offset] = v.x;
    data[offset + 1] = v.y;
    data[offset + 2] = v.width;
    data[offset + 3] = v.height;
  },
  (name, data, offset, uv, v) => {
    v = uv[name];
    data[offset] = v.x;
    data[offset + 1] = v.y;
  },
  (name, data, offset, uv, v) => {
    v = uv[name];
    data[offset] = v.red;
    data[offset + 1] = v.green;
    data[offset + 2] = v.blue;
    data[offset + 3] = v.alpha;
  },
  (name, data, offset, uv, v) => {
    v = uv[name];
    data[offset] = v.red;
    data[offset + 1] = v.green;
    data[offset + 2] = v.blue;
  }
];
var uboSingleFunctionsWGSL = {
  f32: (_name, data, offset, _uv, v) => {
    data[offset] = v;
  },
  i32: (_name, data, offset, _uv, v) => {
    data[offset] = v;
  },
  "vec2<f32>": (_name, data, offset, _uv, v) => {
    data[offset] = v[0];
    data[offset + 1] = v[1];
  },
  "vec3<f32>": (_name, data, offset, _uv, v) => {
    data[offset] = v[0];
    data[offset + 1] = v[1];
    data[offset + 2] = v[2];
  },
  "vec4<f32>": (_name, data, offset, _uv, v) => {
    data[offset] = v[0];
    data[offset + 1] = v[1];
    data[offset + 2] = v[2];
    data[offset + 3] = v[3];
  },
  "mat2x2<f32>": (_name, data, offset, _uv, v) => {
    data[offset] = v[0];
    data[offset + 1] = v[1];
    data[offset + 2] = v[2];
    data[offset + 3] = v[3];
  },
  "mat3x3<f32>": (_name, data, offset, _uv, v) => {
    data[offset] = v[0];
    data[offset + 1] = v[1];
    data[offset + 2] = v[2];
    data[offset + 4] = v[3];
    data[offset + 5] = v[4];
    data[offset + 6] = v[5];
    data[offset + 8] = v[6];
    data[offset + 9] = v[7];
    data[offset + 10] = v[8];
  },
  "mat4x4<f32>": (_name, data, offset, _uv, v) => {
    for (let i = 0; i < 16; i++) {
      data[offset + i] = v[i];
    }
  },
  "mat3x2<f32>": (_name, data, offset, _uv, v) => {
    for (let i = 0; i < 6; i++) {
      data[offset + (i / 3 | 0) * 4 + i % 3] = v[i];
    }
  },
  "mat4x2<f32>": (_name, data, offset, _uv, v) => {
    for (let i = 0; i < 8; i++) {
      data[offset + (i / 4 | 0) * 4 + i % 4] = v[i];
    }
  },
  "mat2x3<f32>": (_name, data, offset, _uv, v) => {
    for (let i = 0; i < 6; i++) {
      data[offset + (i / 2 | 0) * 4 + i % 2] = v[i];
    }
  },
  "mat4x3<f32>": (_name, data, offset, _uv, v) => {
    for (let i = 0; i < 12; i++) {
      data[offset + (i / 4 | 0) * 4 + i % 4] = v[i];
    }
  },
  "mat2x4<f32>": (_name, data, offset, _uv, v) => {
    for (let i = 0; i < 8; i++) {
      data[offset + (i / 2 | 0) * 4 + i % 2] = v[i];
    }
  },
  "mat3x4<f32>": (_name, data, offset, _uv, v) => {
    for (let i = 0; i < 12; i++) {
      data[offset + (i / 3 | 0) * 4 + i % 3] = v[i];
    }
  }
};
var uboSingleFunctionsSTD40 = {
  f32: (_name, data, offset, _uv, v) => {
    data[offset] = v;
  },
  i32: (_name, data, offset, _uv, v) => {
    data[offset] = v;
  },
  "vec2<f32>": (_name, data, offset, _uv, v) => {
    data[offset] = v[0];
    data[offset + 1] = v[1];
  },
  "vec3<f32>": (_name, data, offset, _uv, v) => {
    data[offset] = v[0];
    data[offset + 1] = v[1];
    data[offset + 2] = v[2];
  },
  "vec4<f32>": (_name, data, offset, _uv, v) => {
    data[offset] = v[0];
    data[offset + 1] = v[1];
    data[offset + 2] = v[2];
    data[offset + 3] = v[3];
  },
  "mat2x2<f32>": (_name, data, offset, _uv, v) => {
    data[offset] = v[0];
    data[offset + 1] = v[1];
    data[offset + 4] = v[2];
    data[offset + 5] = v[3];
  },
  "mat3x3<f32>": (_name, data, offset, _uv, v) => {
    data[offset] = v[0];
    data[offset + 1] = v[1];
    data[offset + 2] = v[2];
    data[offset + 4] = v[3];
    data[offset + 5] = v[4];
    data[offset + 6] = v[5];
    data[offset + 8] = v[6];
    data[offset + 9] = v[7];
    data[offset + 10] = v[8];
  },
  "mat4x4<f32>": (_name, data, offset, _uv, v) => {
    for (let i = 0; i < 16; i++) {
      data[offset + i] = v[i];
    }
  },
  "mat3x2<f32>": (_name, data, offset, _uv, v) => {
    for (let i = 0; i < 6; i++) {
      data[offset + (i / 3 | 0) * 4 + i % 3] = v[i];
    }
  },
  "mat4x2<f32>": (_name, data, offset, _uv, v) => {
    for (let i = 0; i < 8; i++) {
      data[offset + (i / 4 | 0) * 4 + i % 4] = v[i];
    }
  },
  "mat2x3<f32>": (_name, data, offset, _uv, v) => {
    for (let i = 0; i < 6; i++) {
      data[offset + (i / 2 | 0) * 4 + i % 2] = v[i];
    }
  },
  "mat4x3<f32>": (_name, data, offset, _uv, v) => {
    for (let i = 0; i < 12; i++) {
      data[offset + (i / 4 | 0) * 4 + i % 4] = v[i];
    }
  },
  "mat2x4<f32>": (_name, data, offset, _uv, v) => {
    for (let i = 0; i < 8; i++) {
      data[offset + (i / 2 | 0) * 4 + i % 2] = v[i];
    }
  },
  "mat3x4<f32>": (_name, data, offset, _uv, v) => {
    for (let i = 0; i < 12; i++) {
      data[offset + (i / 3 | 0) * 4 + i % 3] = v[i];
    }
  }
};

// scripts/folia/node_modules/pixi.js/lib/unsafe-eval/ubo/generateUboSyncPolyfill.mjs
function generateUboSyncPolyfillSTD40(uboElements) {
  return generateUboSyncPolyfill(
    uboElements,
    uboSingleFunctionsSTD40,
    (uboElement) => {
      const rowSize = Math.max(WGSL_TO_STD40_SIZE[uboElement.data.type] / 16, 1);
      const elementSize = uboElement.data.value.length / uboElement.data.size;
      const remainder = (4 - elementSize % 4) % 4;
      return (_name, data, offset, _uv, v) => {
        let t = 0;
        for (let i = 0; i < uboElement.data.size * rowSize; i++) {
          for (let j = 0; j < elementSize; j++) {
            data[offset++] = v[t++];
          }
          offset += remainder;
        }
      };
    }
  );
}
function generateUboSyncPolyfillWGSL(uboElements) {
  return generateUboSyncPolyfill(
    uboElements,
    uboSingleFunctionsWGSL,
    (uboElement) => {
      const { size, align } = WGSL_ALIGN_SIZE_DATA[uboElement.data.type];
      const remainder = (size - align) / 4;
      return (_name, data, offset, _uv, v) => {
        let t = 0;
        for (let i = 0; i < uboElement.data.size * (size / 4); i++) {
          for (let j = 0; j < size / 4; j++) {
            data[offset++] = v[t++];
          }
          offset += remainder;
        }
      };
    }
  );
}
function generateUboSyncPolyfill(uboElements, uboFunctions, arrayUploadFunction) {
  const functionMap = {};
  for (const i in uboElements) {
    const uboElement = uboElements[i];
    const uniform = uboElement.data;
    let parsed = false;
    functionMap[uniform.name] = {
      offset: uboElement.offset / 4,
      func: null
    };
    for (let j = 0; j < uniformParsers.length; j++) {
      const parser = uniformParsers[j];
      if (uniform.type === parser.type && parser.test(uniform)) {
        functionMap[uniform.name].func = uboParserFunctions[j];
        parsed = true;
        break;
      }
    }
    if (!parsed) {
      if (uniform.size === 1) {
        functionMap[uniform.name].func = uboFunctions[uniform.type];
      } else {
        functionMap[uniform.name].func = arrayUploadFunction(uboElement);
      }
    }
  }
  return (uniforms, data, _dataInt32, offset) => {
    for (const i in functionMap) {
      functionMap[i].func(i, data, offset + functionMap[i].offset, uniforms, uniforms[i]);
    }
  };
}

// scripts/folia/node_modules/pixi.js/lib/unsafe-eval/uniforms/uniformSyncFunctions.mjs
var uniformSingleParserFunctions = {
  f32(name, cu, cv, v, ud, _uv, gl) {
    if (cv !== v) {
      cu.value = v;
      gl.uniform1f(ud[name].location, v);
    }
  },
  "vec2<f32>"(name, _cu, cv, v, ud, _uv, gl) {
    if (cv[0] !== v[0] || cv[1] !== v[1]) {
      cv[0] = v[0];
      cv[1] = v[1];
      gl.uniform2f(ud[name].location, v[0], v[1]);
    }
  },
  "vec3<f32>"(name, _cu, cv, v, ud, _uv, gl) {
    if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2]) {
      cv[0] = v[0];
      cv[1] = v[1];
      cv[2] = v[2];
      gl.uniform3f(ud[name].location, v[0], v[1], v[2]);
    }
  },
  "vec4<f32>"(name, _cu, cv, v, ud, _uv, gl) {
    if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2] || cv[3] !== v[3]) {
      cv[0] = v[0];
      cv[1] = v[1];
      cv[2] = v[2];
      cv[3] = v[3];
      gl.uniform4f(ud[name].location, v[0], v[1], v[2], v[3]);
    }
  },
  i32(name, cu, cv, v, ud, _uv, gl) {
    if (cv !== v) {
      cu.value = v;
      gl.uniform1i(ud[name].location, v);
    }
  },
  "vec2<i32>"(name, _cu, cv, v, ud, _uv, gl) {
    if (cv[0] !== v[0] || cv[1] !== v[1]) {
      cv[0] = v[0];
      cv[1] = v[1];
      gl.uniform2i(ud[name].location, v[0], v[1]);
    }
  },
  "vec3<i32>"(name, _cu, cv, v, ud, _uv, gl) {
    if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2]) {
      cv[0] = v[0];
      cv[1] = v[1];
      cv[2] = v[2];
      gl.uniform3i(ud[name].location, v[0], v[1], v[2]);
    }
  },
  "vec4<i32>"(name, _cu, cv, v, ud, _uv, gl) {
    if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2] || cv[3] !== v[3]) {
      cv[0] = v[0];
      cv[1] = v[1];
      cv[2] = v[2];
      cv[3] = v[3];
      gl.uniform4i(ud[name].location, v[0], v[1], v[2], v[3]);
    }
  },
  u32(name, cu, cv, v, ud, _uv, gl) {
    if (cv !== v) {
      cu.value = v;
      gl.uniform1ui(ud[name].location, v);
    }
  },
  "vec2<u32>"(name, _cu, cv, v, ud, _uv, gl) {
    if (cv[0] !== v[0] || cv[1] !== v[1]) {
      cv[0] = v[0];
      cv[1] = v[1];
      gl.uniform2ui(ud[name].location, v[0], v[1]);
    }
  },
  "vec3<u32>"(name, _cu, cv, v, ud, _uv, gl) {
    if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2]) {
      cv[0] = v[0];
      cv[1] = v[1];
      cv[2] = v[2];
      gl.uniform3ui(ud[name].location, v[0], v[1], v[2]);
    }
  },
  "vec4<u32>"(name, _cu, cv, v, ud, _uv, gl) {
    if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2] || cv[3] !== v[3]) {
      cv[0] = v[0];
      cv[1] = v[1];
      cv[2] = v[2];
      cv[3] = v[3];
      gl.uniform4ui(ud[name].location, v[0], v[1], v[2], v[3]);
    }
  },
  bool(name, cu, cv, v, ud, _uv, gl) {
    if (cv !== v) {
      cu.value = v;
      gl.uniform1i(ud[name].location, v);
    }
  },
  "vec2<bool>"(name, _cu, cv, v, ud, _uv, gl) {
    if (cv[0] !== v[0] || cv[1] !== v[1]) {
      cv[0] = v[0];
      cv[1] = v[1];
      gl.uniform2i(ud[name].location, v[0], v[1]);
    }
  },
  "vec3<bool>"(name, _cu, cv, v, ud, _uv, gl) {
    if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2]) {
      cv[0] = v[0];
      cv[1] = v[1];
      cv[2] = v[2];
      gl.uniform3i(ud[name].location, v[0], v[1], v[2]);
    }
  },
  "vec4<bool>"(name, _cu, cv, v, ud, _uv, gl) {
    if (cv[0] !== v[0] || cv[1] !== v[1] || cv[2] !== v[2] || cv[3] !== v[3]) {
      cv[0] = v[0];
      cv[1] = v[1];
      cv[2] = v[2];
      cv[3] = v[3];
      gl.uniform4i(ud[name].location, v[0], v[1], v[2], v[3]);
    }
  },
  "mat2x2<f32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniformMatrix2fv(ud[name].location, false, v);
  },
  "mat3x3<f32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniformMatrix3fv(ud[name].location, false, v);
  },
  "mat4x4<f32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniformMatrix4fv(ud[name].location, false, v);
  }
};
var uniformArrayParserFunctions = {
  f32(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform1fv(ud[name].location, v);
  },
  "vec2<f32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform2fv(ud[name].location, v);
  },
  "vec3<f32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform3fv(ud[name].location, v);
  },
  "vec4<f32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform4fv(ud[name].location, v);
  },
  "mat2x2<f32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniformMatrix2fv(ud[name].location, false, v);
  },
  "mat3x3<f32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniformMatrix3fv(ud[name].location, false, v);
  },
  "mat4x4<f32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniformMatrix4fv(ud[name].location, false, v);
  },
  i32(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform1iv(ud[name].location, v);
  },
  "vec2<i32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform2iv(ud[name].location, v);
  },
  "vec3<i32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform3iv(ud[name].location, v);
  },
  "vec4<i32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform4iv(ud[name].location, v);
  },
  u32(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform1iv(ud[name].location, v);
  },
  "vec2<u32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform2iv(ud[name].location, v);
  },
  "vec3<u32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform3iv(ud[name].location, v);
  },
  "vec4<u32>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform4iv(ud[name].location, v);
  },
  bool(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform1iv(ud[name].location, v);
  },
  "vec2<bool>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform2iv(ud[name].location, v);
  },
  "vec3<bool>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform3iv(ud[name].location, v);
  },
  "vec4<bool>"(name, _cu, _cv, v, ud, _uv, gl) {
    gl.uniform4iv(ud[name].location, v);
  }
};
var uniformParserFunctions = [
  (name, _cu, _cv, _v, ud, uv, gl) => {
    gl.uniformMatrix3fv(ud[name].location, false, uv[name].toArray(true));
  },
  (name, _cu, cv, v, ud, uv, gl) => {
    cv = ud[name].value;
    v = uv[name];
    if (cv[0] !== v.x || cv[1] !== v.y || cv[2] !== v.width || cv[3] !== v.height) {
      cv[0] = v.x;
      cv[1] = v.y;
      cv[2] = v.width;
      cv[3] = v.height;
      gl.uniform4f(ud[name].location, v.x, v.y, v.width, v.height);
    }
  },
  (name, _cu, cv, v, ud, uv, gl) => {
    cv = ud[name].value;
    v = uv[name];
    if (cv[0] !== v.x || cv[1] !== v.y) {
      cv[0] = v.x;
      cv[1] = v.y;
      gl.uniform2f(ud[name].location, v.x, v.y);
    }
  },
  (name, _cu, cv, v, ud, uv, gl) => {
    cv = ud[name].value;
    v = uv[name];
    if (cv[0] !== v.red || cv[1] !== v.green || cv[2] !== v.blue || cv[3] !== v.alpha) {
      cv[0] = v.red;
      cv[1] = v.green;
      cv[2] = v.blue;
      cv[3] = v.alpha;
      gl.uniform4f(ud[name].location, v.red, v.green, v.blue, v.alpha);
    }
  },
  (name, _cu, cv, v, ud, uv, gl) => {
    cv = ud[name].value;
    v = uv[name];
    if (cv[0] !== v.red || cv[1] !== v.green || cv[2] !== v.blue) {
      cv[0] = v.red;
      cv[1] = v.green;
      cv[2] = v.blue;
      gl.uniform3f(ud[name].location, v.red, v.green, v.blue);
    }
  }
];

// scripts/folia/node_modules/pixi.js/lib/unsafe-eval/uniforms/generateUniformsSyncPolyfill.mjs
function generateUniformsSyncPolyfill(group, uniformData) {
  const functionMap = {};
  for (const i in group.uniformStructures) {
    if (!uniformData[i]) continue;
    const uniform = group.uniformStructures[i];
    let parsed = false;
    for (let j = 0; j < uniformParsers.length; j++) {
      const parser = uniformParsers[j];
      if (uniform.type === parser.type && parser.test(uniform)) {
        functionMap[i] = uniformParserFunctions[j];
        parsed = true;
        break;
      }
    }
    if (!parsed) {
      const templateType = uniform.size === 1 ? uniformSingleParserFunctions : uniformArrayParserFunctions;
      functionMap[i] = templateType[uniform.type];
    }
  }
  return (ud, uv, renderer) => {
    const gl = renderer.gl;
    for (const i in functionMap) {
      const v = uv[i];
      const cu = ud[i];
      const cv = ud[i].value;
      functionMap[i](i, cu, cv, v, ud, uv, gl);
    }
  };
}

// scripts/folia/node_modules/pixi.js/lib/unsafe-eval/init.mjs
function selfInstall() {
  Object.assign(AbstractRenderer.prototype, {
    // override unsafeEval check, as we don't need to use it
    _unsafeEvalCheck() {
    }
  });
  Object.assign(UboSystem.prototype, {
    // override unsafeEval check, as we don't need to use it
    _systemCheck() {
    }
  });
  Object.assign(GlUniformGroupSystem.prototype, {
    // use polyfill which avoids eval method
    _generateUniformsSync: generateUniformsSyncPolyfill
  });
  Object.assign(GlUboSystem.prototype, {
    // use polyfill which avoids eval method
    _generateUboSync: generateUboSyncPolyfillSTD40
  });
  Object.assign(GpuUboSystem.prototype, {
    // use polyfill which avoids eval method
    _generateUboSync: generateUboSyncPolyfillWGSL
  });
  Object.assign(GlShaderSystem.prototype, {
    // use polyfill which avoids eval method
    _generateShaderSync: generateShaderSyncPolyfill
  });
  Object.assign(ParticleBuffer.prototype, {
    // use polyfill which avoids eval method
    generateParticleUpdate: generateParticleUpdatePolyfill
  });
}
selfInstall();

// folia:src/components/visualizer/visualizerSeedHash.ts
var hashVisualizerSeed = (value) => {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
};
var createVisualizerRng = (seed) => {
  let state = typeof seed === "number" ? seed >>> 0 : hashVisualizerSeed(seed);
  return () => {
    state = state + 1831565813 | 0;
    let t = Math.imul(state ^ state >>> 15, 1 | state);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
};
var createVisualizerRngAt = (seed, skip) => {
  const state = typeof seed === "number" ? seed >>> 0 : hashVisualizerSeed(seed);
  return createVisualizerRng(state + Math.imul(skip, 1831565813) >>> 0);
};

// folia:src/components/visualizer/lumiere/lumiereRandom.ts
var createRng = createVisualizerRng;
var createRngAt = createVisualizerRngAt;

// folia:src/utils/fontStacks.ts
var MIN_FONT_WEIGHT = 100;
var MAX_FONT_WEIGHT = 900;
var FONT_WEIGHT_STEP = 10;
var normalizeFontWeight = (fontWeight) => {
  if (typeof fontWeight !== "number" || !Number.isFinite(fontWeight)) return null;
  const clamped = Math.min(MAX_FONT_WEIGHT, Math.max(MIN_FONT_WEIGHT, fontWeight));
  return Math.round(clamped / FONT_WEIGHT_STEP) * FONT_WEIGHT_STEP;
};
var resolveThemeFontWeight = (theme, fallback) => normalizeFontWeight(theme?.fontWeight) ?? fallback;
var SUGAR_SERIF_FAMILY = '"\u7345\u5C3E\u56DB\u5B63\u6625\u52A0\u7CD6SC"';
var BUILTIN_FONT_STACKS = {
  sans: '"Inter", "Noto Sans CJK SC", "Noto Sans JP", "Source Han Sans SC", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Helvetica Neue", Arial, sans-serif',
  serif: `${SUGAR_SERIF_FAMILY}, "Iowan Old Style", "Noto Serif CJK SC", "Noto Serif JP", "Source Han Serif SC", "Songti SC", "STSong", "Georgia", serif`,
  mono: '"IBM Plex Mono", "Sarasa Mono SC", "Noto Sans Mono CJK SC", "Noto Sans Mono", "SFMono-Regular", Consolas, monospace'
};
var TRANSLATION_FONT_STACKS = {
  sans: 'system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", "Inter", "Helvetica Neue", Arial, "Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Noto Sans JP", "Source Han Sans JP", "Hiragino Sans", "Yu Gothic", Meiryo, sans-serif',
  serif: `${SUGAR_SERIF_FAMILY}, "Folia Noto Serif SC", "Iowan Old Style", Georgia, "Times New Roman", "Noto Serif CJK SC", "Source Han Serif SC", "Songti SC", "STSong", "SimSun", "Noto Serif JP", "Source Han Serif JP", "Yu Mincho", "MS PMincho", serif`,
  mono: 'Consolas, "IBM Plex Mono", "SFMono-Regular", Menlo, Monaco, "Sarasa Mono SC", "Noto Sans Mono CJK SC", "SimHei", "DengXian", "Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans Mono CJK JP", "MS Gothic", monospace'
};
var CSS_GENERIC_FONT_FAMILIES = /* @__PURE__ */ new Set([
  "serif",
  "sans-serif",
  "monospace",
  "cursive",
  "fantasy",
  "system-ui",
  "ui-serif",
  "ui-sans-serif",
  "ui-monospace",
  "ui-rounded",
  "emoji",
  "math",
  "fangsong"
]);
var quoteFontFamily = (fontFamily) => `"${fontFamily.replace(/["\\]/g, "\\$&")}"`;
var normalizeFontFamilyName = (fontFamily) => fontFamily.trim().replace(/^['"]|['"]$/g, "").trim();
var formatFontFamily = (fontFamily) => {
  const normalized = normalizeFontFamilyName(fontFamily);
  if (!normalized) return null;
  return CSS_GENERIC_FONT_FAMILIES.has(normalized.toLowerCase()) ? normalized : quoteFontFamily(normalized);
};
var normalizeFontFamilyStack = (fontFamilies) => {
  const seen = /* @__PURE__ */ new Set();
  const stack = [];
  fontFamilies?.forEach((fontFamily) => {
    const normalized = normalizeFontFamilyName(fontFamily ?? "");
    if (!normalized) return;
    const key = normalized.toLocaleLowerCase();
    if (seen.has(key)) return;
    seen.add(key);
    stack.push(normalized);
  });
  return stack;
};
var buildCustomFontFamilyStack = (theme) => {
  const familiesToNormalize = [
    ...theme.fontFamily ? [theme.fontFamily] : [],
    ...theme.fontFamilyStack ?? []
  ];
  if (familiesToNormalize.length === 0) {
    return [];
  }
  return normalizeFontFamilyStack(familiesToNormalize).map(formatFontFamily).filter((fontFamily) => Boolean(fontFamily));
};
var getBuiltinThemeFontStack = (fontStyle) => {
  return BUILTIN_FONT_STACKS[fontStyle] ?? BUILTIN_FONT_STACKS.sans;
};
var resolveThemeFontStack = (theme) => {
  const fallbackStack = getBuiltinThemeFontStack(theme.fontStyle);
  const customFontStack = buildCustomFontFamilyStack(theme);
  if (customFontStack.length === 0) {
    return fallbackStack;
  }
  return `${customFontStack.join(", ")}, ${fallbackStack}`;
};

// folia:src/components/visualizer/pixiFilterVertex.ts
var PIXI_FILTER_VERTEX = `
in vec2 aPosition;
out vec2 vTextureCoord;

uniform vec4 uInputSize;
uniform vec4 uOutputFrame;
uniform vec4 uOutputTexture;

void main(void) {
    vec2 position = aPosition * uOutputFrame.zw + uOutputFrame.xy;
    position.x = position.x * (2.0 / uOutputTexture.x) - 1.0;
    position.y = position.y * (2.0 * uOutputTexture.z / uOutputTexture.y) - uOutputTexture.z;
    gl_Position = vec4(position, 0.0, 1.0);
    vTextureCoord = aPosition * (uOutputFrame.zw * uInputSize.zw);
}
`;

// folia:src/components/visualizer/pixi/bloomFilter.ts
var lumiereScaleMask = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET = (102 ^ lumiereScaleMask) + Math.imul(111 ^ lumiereScaleMask, 108 ^ lumiereScaleMask) - ((102 ^ lumiereScaleMask) + Math.imul(111 ^ lumiereScaleMask, 108 ^ lumiereScaleMask));
var downFragment = `
in vec2 vTextureCoord;
out vec4 finalColor;
uniform sampler2D uTexture;
uniform vec4 uInputPixel;
uniform vec4 uInputClamp;
uniform vec4 uParams; // threshold, knee, prefilter(0/1), 0

vec4 tap(vec2 uv) {
    return texture(uTexture, clamp(uv, uInputClamp.xy, uInputClamp.zw));
}

void main(void) {
    vec2 uv = vTextureCoord;
    vec2 hp = uInputPixel.zw;
    vec4 sum = tap(uv) * 4.0;
    sum += tap(uv - hp);
    sum += tap(uv + hp);
    sum += tap(uv + vec2(hp.x, -hp.y));
    sum += tap(uv - vec2(hp.x, -hp.y));
    vec4 c = sum / 8.0;
    if (uParams.z > 0.5) {
        float br = max(c.r, max(c.g, c.b));
        float knee = max(uParams.y, 1e-4);
        float soft = clamp(br - uParams.x + knee, 0.0, 2.0 * knee);
        soft = soft * soft / (4.0 * knee);
        float contrib = max(soft, br - uParams.x) / max(br, 1e-4);
        c *= clamp(contrib, 0.0, 1.0);
    }
    finalColor = c;
}
`;
var upFragment = `
in vec2 vTextureCoord;
out vec4 finalColor;
uniform sampler2D uTexture;
uniform sampler2D uAdd;
uniform vec4 uInputPixel;
uniform vec4 uInputClamp;
uniform vec4 uAddMap;   // uv \u7F29\u653E xy\u3001\u540C\u7EA7\u6743\u91CD\u30010
uniform vec4 uAddClamp;

vec4 tap(vec2 uv) {
    return texture(uTexture, clamp(uv, uInputClamp.xy, uInputClamp.zw));
}

void main(void) {
    vec2 uv = vTextureCoord;
    vec2 hp = uInputPixel.zw;
    vec4 sum = tap(uv + vec2(-hp.x * 2.0, 0.0));
    sum += tap(uv + vec2(-hp.x, hp.y)) * 2.0;
    sum += tap(uv + vec2(0.0, hp.y * 2.0));
    sum += tap(uv + vec2(hp.x, hp.y)) * 2.0;
    sum += tap(uv + vec2(hp.x * 2.0, 0.0));
    sum += tap(uv + vec2(hp.x, -hp.y)) * 2.0;
    sum += tap(uv + vec2(0.0, -hp.y * 2.0));
    sum += tap(uv + vec2(-hp.x, -hp.y)) * 2.0;
    vec4 up = sum / 12.0;
    vec4 same = texture(uAdd, clamp(uv * uAddMap.xy, uAddClamp.xy, uAddClamp.zw));
    finalColor = up + same * uAddMap.z;
}
`;
var combineFragment = `
in vec2 vTextureCoord;
out vec4 finalColor;
uniform sampler2D uTexture;
uniform sampler2D uAdd;
uniform vec4 uInputClamp;
uniform vec4 uAddMap;   // uv \u7F29\u653E xy\u3001\u5F3A\u5EA6\u30010
uniform vec4 uAddClamp;
uniform vec4 uTint;     // \u4E58\u5728 bloom \u4E0A\u7684\u989C\u8272

void main(void) {
    vec4 base = texture(uTexture, clamp(vTextureCoord, uInputClamp.xy, uInputClamp.zw));
    vec4 glow = texture(uAdd, clamp(vTextureCoord * uAddMap.xy, uAddClamp.xy, uAddClamp.zw)) * uAddMap.z;
    vec3 g = glow.rgb * uTint.rgb;
    // \u52A0\u4E0A\u53BB\u7684\u8F89\u5149\u4E5F\u662F\u5149\uFF1A\u9884\u4E58\u3001alpha \u53D6\u6700\u5927\u901A\u9053\uFF08\u4E0E\u5149\u573A\u4E00\u81F4\uFF0C\u8FD1\u4F3C screen\uFF09\u3002
    vec3 rgb = base.rgb + g * (1.0 - base.a * 0.5);
    // \u8D85\u8FC7 1 \u65F6\u6309\u6700\u5927\u901A\u9053\u6574\u4F53\u7F29\u56DE\uFF08\u4FDD\u6301\u91D1\u8272\uFF09\uFF0C\u53EA\u8BA9\u4E00\u5C0F\u90E8\u5206\u53D8\u767D\uFF1B\u9010\u901A\u9053\u622A\u65AD\u4F1A\u628A\u4EAE\u5B57\u70E7\u6210\u767D\u5757\u3002
    float peak = max(max(rgb.r, rgb.g), rgb.b);
    if (peak > 1.0) rgb = mix(rgb / peak, vec3(1.0), 0.2 * (1.0 - 1.0 / peak));
    float a = base.a + max(max(g.r, g.g), g.b) * (1.0 - base.a);
    finalColor = vec4(rgb, min(max(a, max(max(rgb.r, rgb.g), rgb.b)), 1.0));
}
`;
var createBloomFilter = (pixi, initial) => {
  const { Filter, GlProgram, TexturePool, UniformGroup: UniformGroup2 } = pixi;
  const program = (fragment2, name) => GlProgram.from({ vertex: PIXI_FILTER_VERTEX, fragment: fragment2, name });
  const downUniforms = new UniformGroup2({ uParams: { value: new Float32Array(4), type: "vec4<f32>" } });
  const down = new Filter({ glProgram: program(downFragment, "lumiere-bloom-down"), resources: { bloomDown: downUniforms } });
  const upUniforms = new UniformGroup2({
    uAddMap: { value: new Float32Array(4), type: "vec4<f32>" },
    uAddClamp: { value: new Float32Array(4), type: "vec4<f32>" }
  });
  const up = new Filter({
    glProgram: program(upFragment, "lumiere-bloom-up"),
    resources: { bloomUp: upUniforms, uAdd: pixi.Texture.EMPTY.source }
  });
  const combineUniforms = new UniformGroup2({
    uAddMap: { value: new Float32Array(4), type: "vec4<f32>" },
    uAddClamp: { value: new Float32Array(4), type: "vec4<f32>" },
    uTint: { value: new Float32Array([1, 1, 1, 1]), type: "vec4<f32>" }
  });
  const combine = new Filter({
    glProgram: program(combineFragment, "lumiere-bloom-combine"),
    resources: { bloomCombine: combineUniforms, uAdd: pixi.Texture.EMPTY.source }
  });
  const mapFor = (from, to, target, clamp5, weight) => {
    target[0] = from.source.width / to.source.width;
    target[1] = from.source.height / to.source.height;
    target[2] = weight;
    clamp5[0] = 0.5 / to.source.pixelWidth;
    clamp5[1] = 0.5 / to.source.pixelHeight;
    clamp5[2] = to.frame.width / to.source.width - 0.5 / to.source.pixelWidth;
    clamp5[3] = to.frame.height / to.source.height - 0.5 / to.source.pixelHeight;
  };
  class LumiereBloomFilter extends Filter {
    options;
    /** 分遍画用的三个 filter。放在字段上，第一帧之前 linkPixiPrograms 才找得到它们的着色器程序。 */
    passes = [down, up, combine];
    constructor(options) {
      super({ resources: {}, compatibleRenderers: pixi.RendererType.BOTH });
      this.options = { ...options };
      this.padding = options.padding;
    }
    apply(filterManager, input, output, clearMode) {
      const { strength, threshold, knee, levels, spread, tint } = this.options;
      const passThrough = () => {
        mapFor(input, input, combineUniforms.uniforms.uAddMap, combineUniforms.uniforms.uAddClamp, 0);
        combineUniforms.update();
        combine.resources.uAdd = input.source;
        combine.blendMode = this.blendMode;
        filterManager.applyFilter(combine, input, output, clearMode);
      };
      if (strength <= 0) {
        passThrough();
        return;
      }
      const width = input.frame.width;
      const height = input.frame.height;
      const baseResolution = input.source.resolution;
      const chain = [];
      let source = input;
      const count = Math.max(1, Math.min(8 + LUMIERE_NEUTRAL_OFFSET, Math.round(levels)));
      for (let level = 1; level <= count; level += 1) {
        const resolution = baseResolution / 2 ** level;
        if (Math.min(width, height) * resolution < 2) break;
        const target = TexturePool.getOptimalTexture({ width, height, resolution });
        const params = downUniforms.uniforms.uParams;
        params[0] = threshold;
        params[1] = knee;
        params[2] = level === 1 ? 1 : 0;
        downUniforms.update();
        down.blendMode = "normal";
        filterManager.applyFilter(down, source, target, true);
        chain.push(target);
        source = target;
      }
      if (chain.length === 0) {
        passThrough();
        return;
      }
      let current = chain[chain.length - 1];
      const scratch = [];
      for (let index = chain.length - 2; index >= 0; index -= 1) {
        const same = chain[index];
        const target = TexturePool.getOptimalTexture({ width, height, resolution: same.source.resolution });
        mapFor(current, same, upUniforms.uniforms.uAddMap, upUniforms.uniforms.uAddClamp, spread);
        upUniforms.update();
        up.resources.uAdd = same.source;
        up.blendMode = "normal";
        filterManager.applyFilter(up, current, target, true);
        scratch.push(target);
        current = target;
      }
      mapFor(input, current, combineUniforms.uniforms.uAddMap, combineUniforms.uniforms.uAddClamp, strength);
      const tintUniform = combineUniforms.uniforms.uTint;
      tintUniform[0] = tint[0];
      tintUniform[1] = tint[1];
      tintUniform[2] = tint[2];
      combineUniforms.update();
      combine.resources.uAdd = current.source;
      combine.blendMode = this.blendMode;
      filterManager.applyFilter(combine, input, output, clearMode);
      chain.forEach((texture) => TexturePool.returnTexture(texture));
      scratch.forEach((texture) => TexturePool.returnTexture(texture));
    }
    destroy() {
      down.destroy();
      up.destroy();
      combine.destroy();
      super.destroy();
    }
  }
  return new LumiereBloomFilter(initial);
};

// folia:src/components/visualizer/textMeasureCache.ts
var rememberBounded = (cache2, key, value, limit) => {
  if (!cache2.has(key) && cache2.size >= limit) {
    const oldest = cache2.keys().next();
    if (!oldest.done) cache2.delete(oldest.value);
  }
  cache2.set(key, value);
  return value;
};

// folia:src/components/visualizer/colorMix.ts
var isFiniteChannel = (value) => Number.isFinite(value);
var readColor = (normalizedColor) => {
  if (!normalizedColor) return "fallback";
  if (normalizedColor.startsWith("#")) {
    const hex = normalizedColor.slice(1);
    const parse = (value) => Number.parseInt(value, 16);
    if (/^[0-9a-fA-F]{3}$/.test(hex)) {
      return {
        r: parse(hex[0] + hex[0]),
        g: parse(hex[1] + hex[1]),
        b: parse(hex[2] + hex[2])
      };
    }
    if (/^[0-9a-fA-F]{6}$/.test(hex)) {
      return {
        r: parse(hex.slice(0, 2)),
        g: parse(hex.slice(2, 4)),
        b: parse(hex.slice(4, 6))
      };
    }
    return "fallback";
  }
  const rgbMatch = normalizedColor.match(/^rgba?\(([^)]+)\)$/);
  if (rgbMatch) {
    const [r, g, b] = rgbMatch[1].split(",").slice(0, 3).map((part) => Number.parseFloat(part.trim()));
    if ([r, g, b].every(isFiniteChannel)) {
      return { r, g, b };
    }
    return "fallback";
  }
  return "passthrough";
};
var parsedColors = /* @__PURE__ */ new Map();
var PARSED_COLOR_LIMIT = 512;
var parseColor = (color) => {
  const normalized = typeof color === "string" ? color.trim() : "";
  let parsed = parsedColors.get(normalized);
  if (parsed === void 0) {
    parsed = rememberBounded(parsedColors, normalized, readColor(normalized), PARSED_COLOR_LIMIT);
  }
  return { normalized, parsed };
};
var parseColorChannels = (color) => {
  const { parsed } = parseColor(color);
  return typeof parsed === "string" ? null : { ...parsed };
};

// folia:src/components/visualizer/lumiere/color.ts
var lumiereScaleMask2 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET2 = (3137093123 ^ lumiereScaleMask2) + Math.imul(998123833 ^ lumiereScaleMask2, 2021278663 ^ lumiereScaleMask2) - ((3137093123 ^ lumiereScaleMask2) + Math.imul(998123833 ^ lumiereScaleMask2, 2021278663 ^ lumiereScaleMask2));
var rgbOf = (color, fallback = [1, 1, 1]) => {
  const channels = parseColorChannels(color);
  return channels ? [channels.r / 255, channels.g / 255, channels.b / 255] : fallback;
};
var mixRgb = (a, b, amount) => [
  a[0] + (b[0] - a[0]) * amount,
  a[1] + (b[1] - a[1]) * amount,
  a[2] + (b[2] - a[2]) * amount
];
var scaleRgb = (a, k) => [a[0] * k, a[1] * k, a[2] * k];
var hexOf = (rgb) => {
  const c = (v) => Math.round(Math.min(1, Math.max(0, v)) * 255);
  return c(rgb[0]) << 16 | c(rgb[1]) << 8 | c(rgb[2]);
};
var luminance = (rgb) => 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
var WHITE = [1, 1, 1];
var CHAMPAGNE = [1, 0.86 + LUMIERE_NEUTRAL_OFFSET2, 0.62];

// folia:src/components/visualizer/lumiere/light/crossBurst.ts
var lumiereScaleMask3 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET3 = (126 ^ lumiereScaleMask3) + Math.imul(41 ^ lumiereScaleMask3, 57 ^ lumiereScaleMask3) - ((126 ^ lumiereScaleMask3) + Math.imul(41 ^ lumiereScaleMask3, 57 ^ lumiereScaleMask3));
var MAX_BURSTS = 14 + LUMIERE_NEUTRAL_OFFSET3;
var BURST_DURATION = 0.6;
var SWEEP_STEP = 0.07;
var planBursts = (spec, lines, seed) => {
  const triggers2 = [];
  lines.forEach((line2, lineIndex) => {
    if (lineIndex < spec.offset || (lineIndex - spec.offset) % Math.max(1, spec.every) !== 0) return;
    const rng = createRng(`${seed}:burst:${lineIndex}`);
    const chosen = line2.glyphs.filter(() => rng() < spec.density);
    if (chosen.length === 0 && line2.glyphs.length > 0) chosen.push(line2.glyphs[Math.floor(rng() * line2.glyphs.length)]);
    const sweepStart = line2.glyphs[0]?.start ?? 0;
    chosen.forEach((glyph, order) => triggers2.push({
      lineIndex,
      glyphIndex: glyph.glyphIndex,
      time: spec.mode === "sweep" ? sweepStart + order * SWEEP_STEP : glyph.start,
      size: 0.7 + rng() * 0.6,
      dy: (rng() - 0.5) * 0.9
    }));
  });
  return triggers2.sort((a, b) => a.time - b.time);
};
var clamp01 = (value) => Math.min(1, Math.max(0, value));
var easeOutExpo = (value) => {
  const t = clamp01(value);
  return t >= 1 ? 1 : 1 - 2 ** (-10 * t);
};
var easeOutCubic = (value) => 1 - (1 - clamp01(value)) ** 3;
var burstLightBoost = (age) => age < 0 ? 0 : 0.18 * Math.exp(-age / 0.1);
var createCrossBurst = (pixi, options) => {
  const { sprites } = options;
  const view = new pixi.Container();
  const pool = Array.from({ length: MAX_BURSTS }, () => {
    const holder = new pixi.Container();
    const make = (texture) => {
      const sprite = new pixi.Sprite(texture);
      sprite.anchor.set(0.5);
      holder.addChild(sprite);
      return sprite;
    };
    const ring = make(sprites.bokeh);
    const verticalGlow = make(sprites.streak);
    const horizontalGlow = make(sprites.streak);
    const verticalCore = make(sprites.streak);
    const horizontalCore = make(sprites.streak);
    const flash = make(sprites.dot);
    verticalGlow.rotation = Math.PI / 2;
    verticalCore.rotation = Math.PI / 2;
    holder.visible = false;
    view.addChild(holder);
    return { holder, flash, verticalGlow, verticalCore, horizontalGlow, horizontalCore, ring };
  });
  const update = (events) => {
    pool.forEach((burst2, index) => {
      const event = events[index];
      if (!event || event.age < 0 || event.age > BURST_DURATION) {
        burst2.holder.visible = false;
        return;
      }
      burst2.holder.visible = true;
      const { age } = event;
      const L = event.length;
      const glowColor = hexOf(event.color);
      const coreColor = hexOf(mixRgb(event.color, WHITE, 0.75));
      const envelope = clamp01(age / 0.03) * Math.exp(-Math.max(0, age - 0.03) / 0.16);
      const spread = 1 + age * 2;
      burst2.holder.position.set(event.x, event.y);
      const verticalLength = L * easeOutExpo(age / 0.08);
      for (const [sprite, thickness, alpha, tint] of [
        [burst2.verticalGlow, L * 0.1 * spread, 0.6, glowColor],
        [burst2.verticalCore, L * 0.02 * spread, 1, coreColor]
      ]) {
        sprite.position.set(0, -L * 0.2);
        sprite.width = Math.max(1, verticalLength);
        sprite.height = thickness;
        sprite.alpha = alpha * envelope;
        sprite.tint = tint;
      }
      const horizontalLength = L * 0.62 * easeOutExpo((age - 0.02) / 0.1);
      for (const [sprite, thickness, alpha, tint] of [
        [burst2.horizontalGlow, L * 0.09 * spread, 0.55, glowColor],
        [burst2.horizontalCore, L * 0.018 * spread, 0.95, coreColor]
      ]) {
        sprite.position.set(0, -L * 0.42);
        sprite.width = Math.max(1, horizontalLength);
        sprite.height = thickness;
        sprite.alpha = alpha * envelope * clamp01((age - 0.02) / 0.03);
        sprite.tint = tint;
      }
      const flashSize = L * (0.35 + age * 0.8);
      burst2.flash.position.set(0, -L * 0.42);
      burst2.flash.width = flashSize;
      burst2.flash.height = flashSize;
      burst2.flash.alpha = Math.exp(-age / 0.07);
      burst2.flash.tint = coreColor;
      const ring = easeOutCubic(age / 0.4);
      const ringSize = L * 0.9 * ring;
      burst2.ring.position.set(0, -L * 0.42);
      burst2.ring.width = ringSize;
      burst2.ring.height = ringSize;
      burst2.ring.alpha = 0.35 * (1 - ring) * clamp01(age / 0.03);
      burst2.ring.tint = glowColor;
    });
  };
  return {
    view,
    update,
    destroy: () => view.destroy({ children: true })
  };
};

// folia:src/components/visualizer/lumiere/light/rig.ts
var lumiereScaleMask4 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET4 = (979 ^ lumiereScaleMask4) + Math.imul(1192 ^ lumiereScaleMask4, 349 ^ lumiereScaleMask4) - ((979 ^ lumiereScaleMask4) + Math.imul(1192 ^ lumiereScaleMask4, 349 ^ lumiereScaleMask4));
var MAX_BEAMS = 6 + LUMIERE_NEUTRAL_OFFSET4;
var GOBO_PATTERN_ID = { blinds: 1, cross: 2, lattice: 3, leaves: 4 };
var WAVE_MODE_ID = { rings: 1, slits: 2, sources: 3, airy: 4 };
var AUDIO_GAIN = 0.15;
var audioLift = (bass) => 1 + AUDIO_GAIN * Math.max(0, bass) ** 1.5;
var oscillate = (osc, time) => osc ? osc.amplitude * Math.sin((time / Math.max(osc.period, 1e-3) + osc.phase) * Math.PI * 2) : 0;
var resolveBeams = (rig2, time, aspect, drive) => rig2.beams.slice(0, MAX_BEAMS).map((beam) => {
  const angle = beam.angle + oscillate(beam.sway, time);
  const pulse = 1 + oscillate(beam.pulse, time);
  const tint = beam.tint ?? [1, 1, 1];
  const reveal = beam.reveal && drive.local !== void 0 ? 0.06 + 0.94 * smoothstep(0, 1, drive.local / beam.reveal) : 1;
  return {
    ox: beam.x * aspect,
    oy: beam.y,
    dx: Math.cos(angle),
    dy: Math.sin(angle),
    halfWidth: (beam.width ?? 0) / 2,
    tanSpread: Math.tan(beam.spread),
    softness: beam.softness,
    length: beam.length * reveal,
    intensity: beam.intensity * pulse * drive.intensity * audioLift(drive.bass),
    streaks: beam.streaks,
    streakFreq: beam.streakFreq,
    streakPhase: time * beam.streakSpeed,
    core: beam.core ?? 0.5,
    r: tint[0] * drive.color[0],
    g: tint[1] * drive.color[1],
    b: tint[2] * drive.color[2],
    goboPattern: beam.gobo ? GOBO_PATTERN_ID[beam.gobo.pattern] : 0,
    goboFreq: beam.gobo?.frequency ?? 0,
    goboDuty: beam.gobo?.duty ?? 1,
    goboPhase: (beam.gobo?.drift ?? 0) * time,
    spectrum: beam.spectrum ?? 0,
    reach: beam.reach ?? 0
  };
});
var fract = (value) => value - Math.floor(value);
var hash11 = (input) => {
  let p = fract(input * 0.1031);
  p *= p + 33.33;
  p *= p + p;
  return fract(p);
};
var valueNoise1 = (x) => {
  const i = Math.floor(x);
  const f = x - i;
  const u = f * f * (3 - 2 * f);
  return hash11(i) * (1 - u) + hash11(i + 1) * u;
};
var smoothstep = (edge0, edge1, x) => {
  const t = Math.min(1, Math.max(0, (x - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
};
var hash12 = (x, y) => {
  let a = fract(x * 0.1031);
  let b = fract(y * 0.1031);
  let c = fract(x * 0.1031);
  const d = a * (b + 33.33) + b * (c + 33.33) + c * (a + 33.33);
  a += d;
  b += d;
  c += d;
  return fract((a + b) * c);
};
var valueNoise2 = (x, y) => {
  const ix = Math.floor(x);
  const iy = Math.floor(y);
  const fx = x - ix;
  const fy = y - iy;
  const ux = fx * fx * (3 - 2 * fx);
  const uy = fy * fy * (3 - 2 * fy);
  const a = hash12(ix, iy);
  const b = hash12(ix + 1, iy);
  const c = hash12(ix, iy + 1);
  const d = hash12(ix + 1, iy + 1);
  return (a * (1 - ux) + b * ux) * (1 - uy) + (c * (1 - ux) + d * ux) * uy;
};
var band = (x, duty) => {
  const f = fract(x);
  return 1 - smoothstep(duty - 0.06, duty + 0.06, f) + smoothstep(1 - 0.06, 1, f);
};
var GOBO_LEAK = 0.12;
var goboMask = (pattern, frequency, duty, phase, u, v) => pattern > 0 ? GOBO_LEAK + (1 - GOBO_LEAK) * goboPattern(pattern, frequency, duty, phase, u, v) : 1;
var goboPattern = (pattern, frequency, duty, phase, u, v) => {
  if (pattern === 1) return Math.min(1, band(u * frequency * 0.5 + phase, duty));
  if (pattern === 2) return smoothstep(duty * 0.5, duty * 0.5 + 0.08, Math.abs(u));
  if (pattern === 3) {
    return Math.min(1, band(u * frequency * 0.5 + v * frequency * 0.8 + phase, duty)) * Math.min(1, band(u * frequency * 0.5 - v * frequency * 0.8 - phase, duty));
  }
  if (pattern === 4) return smoothstep(duty - 0.12, duty + 0.12, valueNoise2(u * frequency, v * frequency * 0.6 + phase));
  return 1;
};
var beamMask = (beam, x, y) => {
  const px = x - beam.ox;
  const py = y - beam.oy;
  const along = px * beam.dx + py * beam.dy;
  if (along <= 0) return 0;
  const perp = Math.abs(px * -beam.dy + py * beam.dx);
  const half = Math.abs(beam.halfWidth + along * beam.tanSpread) + 1e-4;
  const s = perp / half;
  const edge = smoothstep(1, 1 - Math.max(beam.softness, 0.02), s);
  if (edge <= 0) return 0;
  const signed = s * Math.sign(px * -beam.dy + py * beam.dx);
  const streak = 1 - beam.streaks + beam.streaks * valueNoise1(signed * beam.streakFreq + beam.streakPhase);
  const core = 1 - beam.core + beam.core * (1 - s * s);
  const falloff = Math.exp(-along / Math.max(beam.length, 1e-3));
  const gobo = beam.goboPattern > 0 ? goboMask(beam.goboPattern, beam.goboFreq, beam.goboDuty, beam.goboPhase, signed, along) : 1;
  const reach = beam.reach > 0 ? 1 - smoothstep(beam.reach - Math.max(0.04, half * 2.5), beam.reach, along) : 1;
  const start = smoothstep(0, Math.abs(beam.halfWidth) * 2 + 0.01, along);
  return edge * streak * core * falloff * gobo * reach * start * beam.intensity;
};
var lightAt = (beams, x, y) => {
  let sum = 0;
  for (const beam of beams) sum += beamMask(beam, x, y);
  return sum;
};
var compressLight = (value) => 1 - Math.exp(-value);

// folia:src/components/visualizer/lumiere/light/lightFieldShader.ts
var lumiereScaleMask5 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET5 = (105 ^ lumiereScaleMask5) + Math.imul(97 ^ lumiereScaleMask5, 3137093123 ^ lumiereScaleMask5) - ((105 ^ lumiereScaleMask5) + Math.imul(97 ^ lumiereScaleMask5, 3137093123 ^ lumiereScaleMask5));
var vertex = `
in vec2 aPosition;
out vec2 vPos;
out float vAlpha;

uniform mat3 uProjectionMatrix;
uniform mat3 uWorldTransformMatrix;
uniform vec4 uWorldColorAlpha;
uniform mat3 uTransformMatrix;
uniform vec4 uColor;

void main(void) {
    mat3 mvp = uProjectionMatrix * uWorldTransformMatrix * uTransformMatrix;
    gl_Position = vec4((mvp * vec3(aPosition, 1.0)).xy, 0.0, 1.0);
    vPos = aPosition;
    vAlpha = uColor.a * uWorldColorAlpha.a;
}
`;
var fragment = `
precision highp float;
in vec2 vPos;
in float vAlpha;
out vec4 finalColor;

#define MAX_BEAMS ${MAX_BEAMS}

uniform vec4 uBeamA[MAX_BEAMS]; // ox, oy, dx, dy
uniform vec4 uBeamB[MAX_BEAMS]; // halfWidth, tanSpread, softness, length
uniform vec4 uBeamC[MAX_BEAMS]; // intensity, streaks, streakFreq, streakPhase
uniform vec4 uBeamD[MAX_BEAMS]; // r, g, b, core
uniform vec4 uBeamE[MAX_BEAMS]; // \u7A97\u5F71\uFF1Apattern, frequency, duty, phase
uniform vec4 uBeamF[MAX_BEAMS]; // \u8272\u6563, \u5C04\u7A0B, 0, 0
uniform vec4 uFrame;            // width, height, time, beamCount
uniform vec4 uFogA;             // density, tyndallBase, scale, warp
uniform vec4 uFogB;             // driftX, driftY, ambient, octaves
uniform vec3 uFogColor;
uniform vec4 uGlare;            // x, y, radius, intensity
uniform vec4 uGlareB;           // streak, 0, 0, 0
uniform vec3 uGlareColor;
uniform vec4 uDark;             // \u6697\u573A\u5E95\uFF1A\u9884\u4E58\u989C\u8272 rgb\u3001alpha
uniform vec4 uCaustic;          // \u7126\u6563\uFF1Ascale, speed, inBeam, enabled
uniform vec4 uCausticFloor;     // \u6C60\u5E95\uFF1Acx, cy, rx, ry\uFF08\u9AD8\u5EA6\u5355\u4F4D\uFF09
uniform vec4 uCausticB;         // \u6C60\u5E95\u4EAE\u5EA6, 0, 0, 0
uniform vec4 uWave;             // \u5E72\u6D89\uFF1Amode, frequency, speed, strength
uniform vec4 uWaveB;            // cx, cy, radius, separation\uFF08\u9AD8\u5EA6\u5355\u4F4D\uFF09
uniform vec4 uShield;           // \u6587\u5B57\u533A\uFF1Acx, cy, rx, ry\uFF08\u9AD8\u5EA6\u5355\u4F4D\uFF09
uniform vec4 uShieldB;          // x\uFF1A\u6587\u5B57\u533A\u91CC\u6761\u7EB9\u538B\u6697\u591A\u5C11

float hash11(float x) {
    float p = fract(x * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float valueNoise1(float x) {
    float i = floor(x);
    float f = x - i;
    float u = f * f * (3.0 - 2.0 * f);
    return mix(hash11(i), hash11(i + 1.0), u);
}

float valueNoise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = p - i;
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p, float octaves) {
    float sum = 0.0;
    float amp = 0.5;
    float norm = 0.0;
    mat2 rot = mat2(0.8, -0.6, 0.6, 0.8);
    for (int i = 0; i < 6; i++) {
        if (float(i) >= octaves) break;
        sum += amp * valueNoise2(p);
        norm += amp;
        p = rot * p * 2.03 + vec2(17.1, 9.2);
        amp *= 0.5;
    }
    return sum / max(norm, 1e-4);
}

float fog(vec2 p, float t) {
    vec2 drift = uFogB.xy * t;
    vec2 q = (p - drift) * uFogA.z;
    float octaves = uFogB.w;
    vec2 w = vec2(
        fbm(q + vec2(0.0, t * 0.07), 3.0),
        fbm(q + vec2(5.2, 1.3) - vec2(t * 0.05, 0.0), 3.0)
    );
    float n = fbm(q + uFogA.w * (w - 0.5) * 2.0, octaves);
    // \u62C9\u5F00\u5BF9\u6BD4\uFF1A\u70DF\u662F\u4E00\u7F15\u4E00\u7F15\u7684\uFF0C\u4E0D\u662F\u5747\u5300\u7684\u7070\u3002
    return smoothstep(0.28, 0.82, n);
}

// \u900F\u5149\u6761\uFF1Afract(x) \u843D\u5728 [0, duty) \u91CC\u4E3A 1\uFF0C\u8FB9\u7F18\u67D4\u5316\uFF08\u4E0E rig.ts \u7684 band \u76F8\u540C\uFF09\u3002
float band(float x, float duty) {
    float f = fract(x);
    return min(1.0, 1.0 - smoothstep(duty - 0.06, duty + 0.06, f) + smoothstep(0.94, 1.0, f));
}

// \u7A97\u5F71\u56FE\u6837\uFF1Au \u4E3A\u622A\u9762\u6A2A\u5411\u4F4D\u7F6E -1..1\uFF0Cv \u4E3A\u6CBF\u5149\u675F\u7684\u8DDD\u79BB\u3002
float goboPattern(vec4 E, float u, float v) {
    float pattern = E.x;
    if (pattern < 1.5) return band(u * E.y * 0.5 + E.w, E.z);
    if (pattern < 2.5) return smoothstep(E.z * 0.5, E.z * 0.5 + 0.08, abs(u));
    if (pattern < 3.5) return band(u * E.y * 0.5 + v * E.y * 0.8 + E.w, E.z) * band(u * E.y * 0.5 - v * E.y * 0.8 - E.w, E.z);
    return smoothstep(E.z - 0.12, E.z + 0.12, valueNoise2(vec2(u * E.y, v * E.y * 0.6 + E.w)));
}

// \u7A97\u5F71\uFF08\u4E0E rig.ts \u7684 goboMask \u76F8\u540C\uFF09\uFF1A\u5F71\u5B50\u91CC\u4ECD\u900F\u8FC7 12% \u7684\u6563\u5C04\u5149\u3002
float goboMask(vec4 E, float u, float v) {
    if (E.x < 0.5) return 1.0;
    return 0.12 + 0.88 * goboPattern(E, u, v);
}

// \u6570\u7EC4\u4E0B\u6807\u53EA\u80FD\u7528\u5FAA\u73AF\u53D8\u91CF\uFF08GLSL ES 1.0 \u7684\u9650\u5236\uFF09\uFF0C\u6240\u4EE5\u6309\u5206\u91CF\u4F20\u8FDB\u6765\u3002\u8FD4\u56DE (\u5F3A\u5EA6, \u622A\u9762\u6A2A\u5411\u4F4D\u7F6E -1..1)\u3002
vec2 beamMask(vec4 A, vec4 B, vec4 C, float coreAmount, vec4 E, float reach, vec2 p) {
    vec2 d = p - A.xy;
    float along = dot(d, A.zw);
    if (along <= 0.0) return vec2(0.0);
    float signedPerp = d.x * -A.w + d.y * A.z;
    // \u53D6\u7EDD\u5BF9\u503C\uFF1A\u4F1A\u805A\u7684\u5149\u675F\u8FC7\u4E86\u7126\u70B9\u518D\u6563\u5F00\u3002
    float half_ = abs(B.x + along * B.y) + 1e-4;
    float s = abs(signedPerp) / half_;
    float edge = smoothstep(1.0, 1.0 - max(B.z, 0.02), s);
    if (edge <= 0.0) return vec2(0.0);
    float signedS = s * sign(signedPerp);
    float streak = 1.0 - C.y + C.y * valueNoise1(signedS * C.z + C.w);
    float core = 1.0 - coreAmount + coreAmount * (1.0 - s * s);
    float falloff = exp(-along / max(B.w, 0.001));
    float reachMask = reach > 0.0 ? 1.0 - smoothstep(reach - max(0.04, half_ * 2.5), reach, along) : 1.0;
    float start = smoothstep(0.0, abs(B.x) * 2.0 + 0.01, along);
    return vec2(edge * streak * core * falloff * goboMask(E, signedS, along) * reachMask * start * C.x, signedS);
}

// \u8272\u6563\uFF1A\u622A\u9762\u6A2A\u5411\u4F4D\u7F6E -> \u5149\u8C31\u8272\uFF08\u7EA2\u5728\u4E00\u4FA7\u3001\u7D2B\u5728\u53E6\u4E00\u4FA7\uFF09\u3002
vec3 spectrumColor(float u) {
    float h = clamp(0.5 + 0.5 * u, 0.0, 1.0) * 0.8;
    vec3 k = clamp(abs(fract(vec3(h) + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    return mix(vec3(1.0), k, 0.85);
}

// \u7126\u6563\uFF08\u6C34\u9762\u7126\u6563\u7684\u7ECF\u5178\u8FED\u4EE3\uFF0C\u53BB\u6389\u53D6\u6A21\uFF0C\u8FDE\u7EED\u4E0D\u63A5\u7F1D\uFF09\u3002
float causticField(vec2 p, float t) {
    vec2 q = p * uCaustic.x * 6.2831853 - 250.0;
    vec2 i = q;
    float c = 1.0;
    float inten = 0.005;
    for (int n = 0; n < 4; n++) {
        float tt = t * (1.0 - (3.5 / float(n + 1)));
        i = q + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
        c += 1.0 / length(vec2(q.x / (sin(i.x + tt) / inten), q.y / (cos(i.y + tt) / inten)));
    }
    c /= 4.0;
    c = 1.17 - pow(c, 1.4);
    return clamp(pow(abs(c), 8.0), 0.0, 3.0);
}

// \u5E72\u6D89\u4E0E\u884D\u5C04\uFF1A\u5728\u4E00\u5757\u5706\u5F62\u533A\u57DF\u91CC\u53D1\u5149\u7684\u6761\u7EB9\u3002
float wavePattern(vec2 p, float t) {
    vec2 d = p - uWaveB.xy;
    float radius = max(uWaveB.z, 1e-3);
    float r = length(d) / radius;
    float mask = smoothstep(1.0, 0.55, r);
    float mode = uWave.x;
    float f = uWave.y;
    float phase = t * uWave.z;
    float v;
    if (mode < 1.5) {
        v = 0.5 + 0.5 * cos(r * r * f * 6.0 - phase);
    } else if (mode < 2.5) {
        // \u53CC\u7F1D\uFF1A\u6761\u7EB9\u79BB\u4E2D\u5FC3\u8D8A\u8FDC\u8D8A\u5F2F\uFF08\u53CC\u66F2\u7EBF\uFF09\uFF0C\u5305\u7EDC\u662F\u692D\u5706\uFF0C\u4E0D\u662F\u77E9\u5F62\u3002
        float x = d.x / radius;
        float y = d.y / radius;
        float xc = x * (1.0 + 0.35 * y * y);
        v = pow(cos(xc * f * 3.0 - phase * 0.3), 2.0) * exp(-xc * xc * 2.5);
        mask = smoothstep(1.0, 0.25, length(vec2(x * 0.85, y * 1.5)));
    } else if (mode < 3.5) {
        vec2 s1 = vec2(-uWaveB.w * 0.5, 0.0);
        float d1 = length(d - s1);
        float d2 = length(d + s1);
        v = (0.5 + 0.5 * cos((d1 - d2) * f * 20.0)) * (0.5 + 0.5 * cos((d1 + d2) * f * 6.0 - phase));
    } else {
        float x = r * f * 4.0 + 1e-3;
        float sc = sin(x) / x;
        v = min(sc * sc * 4.0, 1.5);
    }
    // \u6587\u5B57\u533A\u91CC\u538B\u6697\uFF0C\u5B57\u538B\u5728\u6761\u7EB9\u4E0A\u8FD8\u8BFB\u5F97\u6E05\u3002
    vec2 q = (p - uShield.xy) / max(uShield.zw, vec2(1e-3));
    float shield = 1.0 - uShieldB.x * smoothstep(1.0, 0.35, length(q));
    return v * mask * shield * uWave.w;
}

void main(void) {
    float H = uFrame.y;
    float t = uFrame.z;
    vec2 p = vPos / H;

    float density = fog(p, t);
    float tyndall = uFogA.y + (1.0 - uFogA.y) * density * uFogA.x;

    float caustic = uCaustic.w > 0.5 ? causticField(p, t * uCaustic.y + 23.0) : 0.0;
    float causticLift = mix(1.0, 0.25 + 1.5 * caustic, uCaustic.w > 0.5 ? uCaustic.z : 0.0);

    vec3 light = vec3(0.0);
    int count = int(uFrame.w + 0.5);
    for (int i = 0; i < MAX_BEAMS; i++) {
        if (i >= count) break;
        vec4 D = uBeamD[i];
        vec2 m = beamMask(uBeamA[i], uBeamB[i], uBeamC[i], D.w, uBeamE[i], uBeamF[i].y, p);
        vec3 color = D.rgb;
        float spectrum = uBeamF[i].x;
        if (spectrum > 0.0) color = mix(color, spectrumColor(m.y) * max(max(color.r, color.g), color.b), spectrum);
        light += color * m.x;
    }
    light *= tyndall * causticLift;

    // \u6C60\u5E95\u7684\u7126\u6563\u5149\u6591\uFF08\u4E0D\u9760\u70DF\uFF0C\u76F4\u63A5\u4EAE\uFF09\u3002
    if (uCaustic.w > 0.5 && uCausticB.x > 0.0) {
        vec2 e = (p - uCausticFloor.xy) / max(uCausticFloor.zw, vec2(1e-3));
        light += uFogColor * caustic * uCausticB.x * smoothstep(1.0, 0.6, length(e));
    }
    // \u5E72\u6D89\u6761\u7EB9\u3002
    if (uWave.x > 0.5) light += uFogColor * wavePattern(p, t);

    // \u5149\u675F\u4E4B\u5916\u7684\u70DF\uFF1A\u5F88\u6DE1\uFF0C\u53EA\u7ED9\u6697\u573A\u4E00\u70B9\u7A7A\u95F4\u611F\u3002
    light += uFogColor * density * uFogB.z;

    // \u5149\u6E90\u7729\u5149\uFF1A\u4EAE\u6838 + \u5927\u534A\u5F84\u67D4\u5149 + \u6A2A\u5411\u62C9\u4E1D\u3002
    if (uGlare.w > 0.0) {
        vec2 g = p - uGlare.xy;
        float r = max(uGlare.z, 1e-3);
        float dist = length(g);
        float glare = exp(-dist / r) * 0.55 + exp(-(dist * dist) / (r * r * 0.03));
        float streak = exp(-abs(g.y) / (r * 0.035)) * exp(-abs(g.x) / (r * 7.0)) * uGlareB.x;
        light += uGlareColor * (glare + streak) * uGlare.w;
    }

    // \u4FDD\u6301\u8272\u76F8\u7684\u538B\u7F29\uFF1A\u6309\u6700\u5927\u901A\u9053\u538B\u5230 0..1\uFF0C\u53EA\u5728\u6781\u4EAE\u5904\u5FAE\u5FAE\u53D1\u767D\uFF08\u9010\u901A\u9053\u538B\u7F29\u4F1A\u628A\u91D1\u8272\u538B\u6210\u767D\u8272\uFF09\u3002
    float peak = max(max(light.r, light.g), light.b);
    float mapped = 1.0 - exp(-peak);
    vec3 c = peak > 1e-5 ? light / peak * mapped : vec3(0.0);
    c = mix(c, vec3(mapped), 0.3 * mapped * mapped * mapped);
    // \u6296\u52A8\uFF0C\u514D\u5F97\u6697\u90E8\u6E10\u53D8\u5728 8 \u4F4D\u89C6\u9891\u91CC\u51FA\u8272\u5E26\uFF08\u6309\u50CF\u7D20\u5750\u6807\uFF0C\u786E\u5B9A\u6027\uFF09\u3002
    c += (hash12(gl_FragCoord.xy) - 0.5) / 255.0;
    c = clamp(c, 0.0, 1.0);
    float a = max(max(c.r, c.g), c.b);

    // \u53E0\u5728\u6697\u573A\u5E95\u4E0A\uFF08\u9884\u4E58\u7684 over\uFF09\u3002
    vec3 rgb = c + uDark.rgb * (1.0 - a);
    float alpha = a + uDark.a * (1.0 - a);
    finalColor = vec4(rgb, alpha) * vAlpha;
}
`;
var createLightField = (pixi, width, height, margin = 0) => {
  const x0 = -margin;
  const y0 = -margin;
  const x1 = width + margin;
  const y1 = height + margin;
  const geometry = new pixi.Geometry({
    attributes: {
      aPosition: [x0, y0, x1, y0, x1, y1, x0, y1]
    },
    indexBuffer: [0, 1, 2, 0, 2, 3]
  });
  const uniforms = new pixi.UniformGroup({
    uBeamA: { value: new Float32Array(MAX_BEAMS * 4), type: "vec4<f32>", size: MAX_BEAMS },
    uBeamB: { value: new Float32Array(MAX_BEAMS * 4), type: "vec4<f32>", size: MAX_BEAMS },
    uBeamC: { value: new Float32Array(MAX_BEAMS * 4), type: "vec4<f32>", size: MAX_BEAMS },
    uBeamD: { value: new Float32Array(MAX_BEAMS * 4), type: "vec4<f32>", size: MAX_BEAMS },
    uBeamE: { value: new Float32Array(MAX_BEAMS * 4), type: "vec4<f32>", size: MAX_BEAMS },
    uBeamF: { value: new Float32Array(MAX_BEAMS * 4), type: "vec4<f32>", size: MAX_BEAMS },
    uFrame: { value: new Float32Array([width, height, 0, 0]), type: "vec4<f32>" },
    uFogA: { value: new Float32Array(4), type: "vec4<f32>" },
    uFogB: { value: new Float32Array(4), type: "vec4<f32>" },
    uFogColor: { value: new Float32Array(3), type: "vec3<f32>" },
    uGlare: { value: new Float32Array(4), type: "vec4<f32>" },
    uGlareB: { value: new Float32Array(4), type: "vec4<f32>" },
    uGlareColor: { value: new Float32Array(3), type: "vec3<f32>" },
    uDark: { value: new Float32Array(4), type: "vec4<f32>" },
    uCaustic: { value: new Float32Array(4), type: "vec4<f32>" },
    uCausticFloor: { value: new Float32Array(4), type: "vec4<f32>" },
    uCausticB: { value: new Float32Array(4), type: "vec4<f32>" },
    uWave: { value: new Float32Array(4), type: "vec4<f32>" },
    uWaveB: { value: new Float32Array(4), type: "vec4<f32>" },
    uShield: { value: new Float32Array(4), type: "vec4<f32>" },
    uShieldB: { value: new Float32Array(4), type: "vec4<f32>" }
  });
  const shader = new pixi.Shader({
    glProgram: pixi.GlProgram.from({ vertex, fragment, name: "lumiere-light-field" }),
    resources: { lightUniforms: uniforms }
  });
  const mesh = new pixi.Mesh({ geometry, shader });
  const u = uniforms.uniforms;
  const update = (frame2) => {
    const { beams, rig: rig2, time } = frame2;
    const A = u.uBeamA, B = u.uBeamB, C = u.uBeamC, D = u.uBeamD, E = u.uBeamE, F = u.uBeamF;
    A.fill(0);
    B.fill(0);
    C.fill(0);
    D.fill(0);
    E.fill(0);
    F.fill(0);
    beams.forEach((beam, index) => {
      const o = index * (4 + LUMIERE_NEUTRAL_OFFSET5);
      A[o] = beam.ox;
      A[o + 1] = beam.oy;
      A[o + 2] = beam.dx;
      A[o + 3] = beam.dy;
      B[o] = beam.halfWidth;
      B[o + 1] = beam.tanSpread;
      B[o + 2] = beam.softness;
      B[o + 3] = beam.length;
      C[o] = beam.intensity;
      C[o + 1] = beam.streaks;
      C[o + 2] = beam.streakFreq;
      C[o + 3] = beam.streakPhase;
      D[o] = beam.r;
      D[o + 1] = beam.g;
      D[o + 2] = beam.b;
      D[o + 3] = beam.core;
      E[o] = beam.goboPattern;
      E[o + 1] = beam.goboFreq;
      E[o + 2] = beam.goboDuty;
      E[o + 3] = beam.goboPhase;
      F[o] = beam.spectrum;
      F[o + 1] = beam.reach;
    });
    u.uFrame[0] = width;
    u.uFrame[1] = height;
    u.uFrame[2] = time;
    u.uFrame[3] = beams.length;
    const fog = rig2.fog;
    u.uFogA[0] = fog.density * frame2.fogScale;
    u.uFogA[1] = fog.tyndallBase;
    u.uFogA[2] = fog.scale;
    u.uFogA[3] = fog.warp;
    u.uFogB[0] = fog.driftX;
    u.uFogB[1] = fog.driftY;
    u.uFogB[2] = fog.ambient * frame2.fogScale;
    u.uFogB[3] = frame2.octaves;
    u.uFogColor[0] = frame2.color[0];
    u.uFogColor[1] = frame2.color[1];
    u.uFogColor[2] = frame2.color[2];
    const glare = rig2.glare;
    const aspect = width / height;
    u.uGlare[0] = glare ? glare.x * aspect : 0;
    u.uGlare[1] = glare ? glare.y : 0;
    u.uGlare[2] = glare ? glare.radius : 0;
    u.uGlare[3] = glare ? glare.intensity * frame2.glareScale : 0;
    u.uGlareB[0] = glare ? glare.streak : 0;
    u.uGlareColor[0] = frame2.color[0];
    u.uGlareColor[1] = frame2.color[1];
    u.uGlareColor[2] = frame2.color[2];
    u.uDark.set(frame2.dark);
    const caustic2 = rig2.caustic;
    u.uCaustic[0] = caustic2?.scale ?? 0;
    u.uCaustic[1] = caustic2?.speed ?? 0;
    u.uCaustic[2] = caustic2?.inBeam ?? 0;
    u.uCaustic[3] = caustic2 ? 1 : 0;
    u.uCausticFloor[0] = (caustic2?.floor?.cx ?? 0) * aspect;
    u.uCausticFloor[1] = caustic2?.floor?.cy ?? 0;
    u.uCausticFloor[2] = (caustic2?.floor?.rx ?? 0) * aspect;
    u.uCausticFloor[3] = caustic2?.floor?.ry ?? 0;
    u.uCausticB[0] = (caustic2?.floor?.strength ?? 0) * frame2.glareScale;
    const wave2 = rig2.wave;
    u.uWave[0] = wave2 ? WAVE_MODE_ID[wave2.mode] : 0;
    u.uWave[1] = wave2?.frequency ?? 0;
    u.uWave[2] = wave2?.speed ?? 0;
    u.uWave[3] = (wave2?.strength ?? 0) * frame2.glareScale;
    u.uWaveB[0] = (wave2?.cx ?? 0) * aspect;
    u.uWaveB[1] = wave2?.cy ?? 0;
    u.uWaveB[2] = wave2?.radius ?? 0;
    u.uWaveB[3] = wave2?.separation ?? 0;
    const region = frame2.textRegion;
    u.uShield[0] = region ? region.cx * aspect : 0;
    u.uShield[1] = region ? region.cy : 0;
    u.uShield[2] = region ? region.w * aspect / 2 : 1;
    u.uShield[3] = region ? region.h / 2 : 1;
    u.uShieldB[0] = region && wave2 ? wave2.shield ?? 0.45 : 0;
    uniforms.update();
  };
  return {
    view: mesh,
    update,
    destroy: () => {
      mesh.destroy();
      geometry.destroy(true);
      shader.destroy();
    }
  };
};

// folia:src/components/visualizer/lumiere/light/motes.ts
var lumiereScaleMask6 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET6 = (443 ^ lumiereScaleMask6) + Math.imul(186 ^ lumiereScaleMask6, 252 ^ lumiereScaleMask6) - ((443 ^ lumiereScaleMask6) + Math.imul(186 ^ lumiereScaleMask6, 252 ^ lumiereScaleMask6));
var wrap = (value, min, max) => {
  const span = max - min;
  return min + ((value - min) % span + span) % span;
};
var createMotes = (pixi, options) => {
  const { width, height, spec, texture } = options;
  const aspect = width / height;
  const rng = createRng(options.seed);
  const view = new pixi.Container();
  const margin = 0.08 + LUMIERE_NEUTRAL_OFFSET6;
  const motes = Array.from({ length: spec.count }, () => {
    const sprite = new pixi.Sprite(texture);
    sprite.anchor.set(0.5);
    view.addChild(sprite);
    const depth = rng();
    return {
      sprite,
      bx: rng() * (aspect + margin * 2) - margin,
      by: rng() * (1 + margin * 2) - margin,
      depth,
      size: spec.sizeMin + (spec.sizeMax - spec.sizeMin) * depth * depth,
      phaseA: rng() * Math.PI * 2,
      phaseB: rng() * Math.PI * 2,
      freqA: 0.6 + rng() * 0.8,
      freqB: 0.5 + rng() * 0.9,
      twinklePhase: rng() * Math.PI * 2,
      twinkleFreq: 0.8 + rng() * 2.2
    };
  });
  const update = (time, beams, color, intensity) => {
    const omega = Math.PI * 2 / Math.max(spec.swirlPeriod, 0.1);
    for (const mote of motes) {
      const speed = 0.45 + mote.depth * 0.9;
      const swirl = spec.swirl * (0.5 + mote.depth);
      const x = wrap(
        mote.bx + spec.driftX * speed * time + swirl * Math.sin(time * omega * mote.freqA + mote.phaseA),
        -margin,
        aspect + margin
      );
      const y = wrap(
        mote.by + spec.driftY * speed * time + swirl * Math.cos(time * omega * mote.freqB + mote.phaseB),
        -margin,
        1 + margin
      );
      const lit = compressLight(lightAt(beams, x, y)) * spec.gain;
      const twinkle = 1 - spec.twinkle + spec.twinkle * (0.5 + 0.5 * Math.sin(time * mote.twinkleFreq * Math.PI * 2 + mote.twinklePhase));
      const alpha = Math.min(1, (lit + spec.ambient) * twinkle * intensity);
      const sprite = mote.sprite;
      sprite.visible = alpha > 4e-3;
      if (!sprite.visible) continue;
      sprite.position.set(x * height, y * height);
      const px = mote.size * height;
      sprite.width = px;
      sprite.height = px;
      sprite.alpha = alpha;
      sprite.tint = color;
    }
  };
  return {
    view,
    update,
    destroy: () => view.destroy({ children: true })
  };
};

// folia:src/components/visualizer/lumiere/light/starfall.ts
var lumiereScaleMask7 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET7 = (62 ^ lumiereScaleMask7) + Math.imul(3 ^ lumiereScaleMask7, 59 ^ lumiereScaleMask7) - ((62 ^ lumiereScaleMask7) + Math.imul(3 ^ lumiereScaleMask7, 59 ^ lumiereScaleMask7));
var starfallIgnition = (spec) => spec.opening * (0.45 + LUMIERE_NEUTRAL_OFFSET7);
var clamp012 = (value) => Math.min(1, Math.max(0, value));
var easeOutCubic2 = (value) => 1 - (1 - clamp012(value)) ** 3;
var createStarfall = (pixi, options) => {
  const { width, height, spec } = options;
  const aspect = width / height;
  const rng = createRng(`${options.seed}:starfall`);
  const view = new pixi.Container();
  const trails = new pixi.Container();
  const points = new pixi.Container();
  view.addChild(trails, points);
  const makeTrail = () => {
    const trail = new pixi.Sprite(options.streak);
    trail.anchor.set(1, 0.5);
    trail.rotation = Math.PI / 2;
    trails.addChild(trail);
    return trail;
  };
  const stars = Array.from({ length: spec.stars }, () => {
    const bright = rng() < 0.08;
    const sprite = new pixi.Sprite(bright ? options.star : options.dot);
    sprite.anchor.set(0.5);
    points.addChild(sprite);
    return {
      sprite,
      trail: makeTrail(),
      x: rng() * aspect,
      // 上密下疏。
      y: 0.02 + rng() ** 1.7 * 0.9,
      fromY: -0.05 - rng() * 0.25,
      // 倾泻：大多数在开场前段落下，少数拖到后段。
      delay: spec.opening * (0.02 + 0.7 * rng() ** 1.4),
      fall: 0.45 + rng() * 0.7,
      size: bright ? 0.018 + rng() * 0.02 : 3e-3 + rng() * 6e-3,
      bright,
      twinklePhase: rng() * Math.PI * 2,
      twinkleFreq: 0.4 + rng() * 1.8
    };
  });
  const drops = Array.from({ length: spec.rain }, () => {
    const sprite = new pixi.Sprite(options.dot);
    sprite.anchor.set(0.5);
    points.addChild(sprite);
    const spread = (rng() + rng() + rng() - 1.5) / 1.5;
    return {
      sprite,
      trail: makeTrail(),
      x: aspect * (0.5 + spread * spec.rainSpread * 0.5),
      period: 1.25 / Math.max(spec.rainSpeed, 0.01) * (0.7 + rng() * 0.6),
      phase: rng(),
      size: 3e-3 + rng() * 5e-3,
      sway: (rng() - 0.5) * 0.02
    };
  });
  const place = (sprite, trail, x, y, size, alpha, speed, color) => {
    sprite.visible = alpha > 4e-3;
    trail.visible = sprite.visible && speed > 0.05;
    if (!sprite.visible) return;
    sprite.position.set(x * height, y * height);
    sprite.width = size * height;
    sprite.height = size * height;
    sprite.alpha = alpha;
    sprite.tint = color;
    if (trail.visible) {
      trail.position.set(x * height, y * height);
      trail.width = Math.min(0.25, speed * 0.09) * height;
      trail.height = Math.max(1.5, size * height * 0.7);
      trail.alpha = alpha * 0.6;
      trail.tint = color;
    }
  };
  const update = (local, time, beams, color, fade) => {
    for (const star of stars) {
      const progress = (local - star.delay) / star.fall;
      if (progress <= 0) {
        star.sprite.visible = false;
        star.trail.visible = false;
        continue;
      }
      const eased = easeOutCubic2(progress);
      const y = star.fromY + (star.y - star.fromY) * eased;
      const speed = progress < 1 ? (star.y - star.fromY) * 3 * (1 - progress) ** 2 / star.fall : 0;
      const landedAt = star.delay + star.fall;
      const flash = local >= landedAt ? Math.exp(-(local - landedAt) / 0.25) : 0;
      const twinkle = 0.55 + 0.45 * Math.sin(time * star.twinkleFreq * Math.PI * 2 + star.twinklePhase);
      const lit = compressLight(lightAt(beams, star.x, y));
      const base = progress < 1 ? 0.9 : (star.bright ? 0.7 : 0.45) * twinkle;
      const alpha = clamp012((base + lit * 0.8 + flash) * spec.brightness * fade);
      place(star.sprite, star.trail, star.x, y, star.size * (1 + flash * 1.5), alpha, speed, color);
    }
    const rainIn = clamp012((local - spec.opening * 0.6) / 1.5);
    for (const drop of drops) {
      const cycle = (time / drop.period + drop.phase) % 1;
      const y = -0.1 + cycle * 1.25;
      const x = drop.x + Math.sin(time * 0.7 + drop.phase * 6) * drop.sway;
      const lit = compressLight(lightAt(beams, x, y));
      const edge = clamp012(cycle / 0.08) * clamp012((1 - cycle) / 0.15);
      const alpha = clamp012((0.18 + lit * 1.1) * edge * rainIn * fade * spec.brightness);
      place(drop.sprite, drop.trail, x, y, drop.size, alpha, 1.25 / drop.period, color);
    }
  };
  return {
    view,
    update,
    destroy: () => view.destroy({ children: true })
  };
};

// folia:src/components/visualizer/lumiere/lineart/lineArt.ts
var lumiereScaleMask8 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET8 = (998123833 ^ lumiereScaleMask8) + Math.imul(2021278663 ^ lumiereScaleMask8, 4898 ^ lumiereScaleMask8) - ((998123833 ^ lumiereScaleMask8) + Math.imul(2021278663 ^ lumiereScaleMask8, 4898 ^ lumiereScaleMask8));
var LINE_ART_UNLOAD_AFTER = 2 + LUMIERE_NEUTRAL_OFFSET8;
var LINE_ART_UNLOAD_LEAD = 4;
var shouldUnloadLineArt = (hiddenSince, time, nextUse) => time - hiddenSince >= LINE_ART_UNLOAD_AFTER && nextUse - time >= LINE_ART_UNLOAD_LEAD;
var cumulative = (points) => {
  const lengths = [0];
  for (let i = 1; i < points.length; i += 1) {
    const [ax, ay] = points[i - 1];
    const [bx, by] = points[i];
    lengths.push(lengths[i - 1] + Math.hypot(bx - ax, by - ay));
  }
  return lengths;
};
var clamp013 = (value) => Math.min(1, Math.max(0, value));
var createLineArt = (pixi, options) => {
  const { height, spec } = options;
  const view = new pixi.Container();
  const pathsHolder = new pixi.Container({ isRenderGroup: true });
  const nodesHolder = new pixi.Container();
  view.addChild(pathsHolder, nodesHolder);
  const paths = spec.paths.filter((path2) => path2.points.length > 1).map((path2) => {
    const graphics = new pixi.Graphics();
    pathsHolder.addChild(graphics);
    const lengths = cumulative(path2.points);
    const mid = path2.points[Math.floor(path2.points.length / 2)];
    return { spec: path2, graphics, lengths, total: lengths[lengths.length - 1], drawn: -1, midpoint: mid };
  });
  const nodes = spec.nodes.map((node2) => {
    const sprite = new pixi.Sprite(options.starTexture);
    sprite.anchor.set(0.5);
    sprite.position.set(node2.at[0] * height, node2.at[1] * height);
    nodesHolder.addChild(sprite);
    return { spec: node2, sprite };
  });
  const redraw = (path2, amount) => {
    const g = path2.graphics;
    g.clear();
    if (amount <= 0) return;
    const { points, dash } = path2.spec;
    const limit = Math.min(amount, path2.total);
    const period = dash ? dash[0] + dash[1] : 0;
    const at = (index, distance) => {
      const [ax, ay] = points[index - 1];
      const [bx, by] = points[index];
      const segment2 = path2.lengths[index] - path2.lengths[index - 1];
      const f = segment2 > 0 ? (distance - path2.lengths[index - 1]) / segment2 : 0;
      return [(ax + (bx - ax) * f) * height, (ay + (by - ay) * f) * height];
    };
    g.moveTo(points[0][0] * height, points[0][1] * height);
    for (let i = 1; i < points.length; i += 1) {
      const start = path2.lengths[i - 1];
      const end = Math.min(path2.lengths[i], limit);
      if (start >= limit) break;
      if (!dash) {
        const [x, y] = at(i, end);
        g.lineTo(x, y);
        continue;
      }
      for (let k = Math.floor(start / period); k * period < end; k += 1) {
        const from = Math.max(start, k * period);
        const to = Math.min(end, k * period + dash[0]);
        if (to <= from) continue;
        const [ax, ay] = at(i, from);
        const [bx, by] = at(i, to);
        g.moveTo(ax, ay);
        g.lineTo(bx, by);
      }
    }
    const px = path2.spec.width * height;
    g.stroke({ width: px * 3.2, color: 16777215, alpha: 0.12, cap: "round", join: "round" });
    g.stroke({ width: px, color: 16777215, alpha: 1, cap: "round", join: "round" });
  };
  let resident = false;
  let hiddenSince = Number.NaN;
  const update = (time, draw, fade, beams, color) => {
    resident = true;
    hiddenSince = Number.NaN;
    for (const path2 of paths) {
      const { delay, span } = path2.spec;
      const local = clamp013((draw - delay) / Math.max(span, 1e-3));
      const eased = 1 - (1 - local) ** 3;
      const amount = eased * path2.total;
      if (Math.abs(amount - path2.drawn) > 1e-5) {
        redraw(path2, amount);
        path2.drawn = amount;
      }
      const lit = compressLight(lightAt(beams, path2.midpoint[0], path2.midpoint[1]));
      path2.graphics.alpha = Math.min(1, path2.spec.alpha * fade * (0.55 + 0.9 * lit));
      path2.graphics.tint = color;
    }
    for (const { spec: node2, sprite } of nodes) {
      const appear = clamp013((draw - node2.delay) / 0.08);
      const lit = compressLight(lightAt(beams, node2.at[0], node2.at[1]));
      const twinkle = 0.55 + 0.45 * Math.sin(time * 2.3 + node2.twinklePhase);
      const alpha = appear * fade * (0.25 + 0.75 * lit) * twinkle;
      sprite.visible = alpha > 4e-3;
      if (!sprite.visible) continue;
      const pop = 1 + (1 - appear) * 1.5;
      const px = node2.size * height * pop * (0.8 + 0.2 * twinkle);
      sprite.width = px;
      sprite.height = px;
      sprite.alpha = alpha;
      sprite.tint = color;
    }
  };
  const idle = (time, nextUse) => {
    if (!resident) return;
    if (!(hiddenSince <= time)) hiddenSince = time;
    if (!shouldUnloadLineArt(hiddenSince, time, nextUse)) return;
    for (const path2 of paths) path2.graphics.context.unload();
    resident = false;
  };
  return {
    view,
    update,
    idle,
    // context: true 必须带上：Pixi 8 的 Graphics.destroy 只要收到选项对象、却没写 context: true，就不销毁它自己建的
    // GraphicsContext。那个 context 还挂在渲染器的 GraphicsContextSystem 里，连同它的 GPU 批数据（一个 batcher、
    // 两块顶点 / 索引缓冲）要等 Pixi 的 GC 空闲 60 秒后才回收；单元换得勤时，WebGL 缓冲会一直涨到那个窗口的量。
    destroy: () => view.destroy({ children: true, context: true })
  };
};
var showLineArtLayer = (holder, layers, index, shown) => {
  const view = layers[index].view;
  if (shown === (view.parent === holder)) return;
  if (!shown) {
    holder.removeChild(view);
    return;
  }
  let position = 0;
  for (let k = 0; k < index; k += 1) if (layers[k].view.parent === holder) position += 1;
  holder.addChildAt(view, position);
};

// folia:src/services/lucideIconResolver.ts
var icons = { "Umbrella": [["path", { "d": "M12 13v7a2 2 0 0 0 4 0" }], ["path", { "d": "M12 2v2" }], ["path", { "d": "M20.992 13a1 1 0 0 0 .97-1.274 10.284 10.284 0 0 0-19.923 0A1 1 0 0 0 3 13z" }]], "Music": [["path", { "d": "M9 18V5l12-2v13" }], ["circle", { "cx": "6", "cy": "18", "r": "3" }], ["circle", { "cx": "18", "cy": "16", "r": "3" }]], "Sparkles": [["path", { "d": "M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z" }], ["path", { "d": "M20 2v4" }], ["path", { "d": "M22 4h-4" }], ["circle", { "cx": "4", "cy": "20", "r": "2" }]], "Snowflake": [["path", { "d": "m10 20-1.25-2.5L6 18" }], ["path", { "d": "M10 4 8.75 6.5 6 6" }], ["path", { "d": "m14 20 1.25-2.5L18 18" }], ["path", { "d": "m14 4 1.25 2.5L18 6" }], ["path", { "d": "m17 21-3-6h-4" }], ["path", { "d": "m17 3-3 6 1.5 3" }], ["path", { "d": "M2 12h6.5L10 9" }], ["path", { "d": "m20 10-1.5 2 1.5 2" }], ["path", { "d": "M22 12h-6.5L14 15" }], ["path", { "d": "m4 10 1.5 2L4 14" }], ["path", { "d": "m7 21 3-6-1.5-3" }], ["path", { "d": "m7 3 3 6h4" }]], "Flower2": [["path", { "d": "M12 5a3 3 0 1 1 3 3m-3-3a3 3 0 1 0-3 3m3-3v1M9 8a3 3 0 1 0 3 3M9 8h1m5 0a3 3 0 1 1-3 3m3-3h-1m-2 3v-1" }], ["circle", { "cx": "12", "cy": "8", "r": "2" }], ["path", { "d": "M12 10v12" }], ["path", { "d": "M12 22c4.2 0 7-1.667 7-5-4.2 0-7 1.667-7 5Z" }], ["path", { "d": "M12 22c-4.2 0-7-1.667-7-5 4.2 0 7 1.667 7 5Z" }]], "Smile": [["circle", { "cx": "12", "cy": "12", "r": "10" }], ["path", { "d": "M8 14s1.5 2 4 2 4-2 4-2" }], ["line", { "x1": "9", "x2": "9.01", "y1": "9", "y2": "9" }], ["line", { "x1": "15", "x2": "15.01", "y1": "9", "y2": "9" }]], "Feather": [["path", { "d": "M14.086 18.412A2 2 0 0112.67 19H5v-7.672a2 2 0 01.586-1.414L11.75 3.75a6 6 0 118.49 8.49z" }], ["path", { "d": "M16 8 2 22" }], ["path", { "d": "M17.488 15H9" }]], "Leaf": [["path", { "d": "M11 20a10 10 0 0010-10 25.9 25.9 0 00-1.04-7.281 1 1 0 00-1.755-.325C15.833 5.5 13 5.5 9.8 6.1A7 7 0 0011 20" }], ["path", { "d": "M2 21a5 5 0 012.911-4.544C7.613 15.212 8.351 15.24 11 13" }]], "Star": [["path", { "d": "M11.525 2.295a.53.53 0 0 1 .95 0l2.31 4.679a2.123 2.123 0 0 0 1.595 1.16l5.166.756a.53.53 0 0 1 .294.904l-3.736 3.638a2.123 2.123 0 0 0-.611 1.878l.882 5.14a.53.53 0 0 1-.771.56l-4.618-2.428a2.122 2.122 0 0 0-1.973 0L6.396 21.01a.53.53 0 0 1-.77-.56l.881-5.139a2.122 2.122 0 0 0-.611-1.879L2.16 9.795a.53.53 0 0 1 .294-.906l5.165-.755a2.122 2.122 0 0 0 1.597-1.16z" }]], "Sun": [["circle", { "cx": "12", "cy": "12", "r": "4" }], ["path", { "d": "M12 2v2" }], ["path", { "d": "M12 20v2" }], ["path", { "d": "m4.93 4.93 1.41 1.41" }], ["path", { "d": "m17.66 17.66 1.41 1.41" }], ["path", { "d": "M2 12h2" }], ["path", { "d": "M20 12h2" }], ["path", { "d": "m6.34 17.66-1.41 1.41" }], ["path", { "d": "m19.07 4.93-1.41 1.41" }]], "CloudRain": [["path", { "d": "M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242" }], ["path", { "d": "M16 14v6" }], ["path", { "d": "M8 14v6" }], ["path", { "d": "M12 16v6" }]], "Flower": [["circle", { "cx": "12", "cy": "12", "r": "3" }], ["path", { "d": "M12 16.5A4.5 4.5 0 1 1 7.5 12 4.5 4.5 0 1 1 12 7.5a4.5 4.5 0 1 1 4.5 4.5 4.5 4.5 0 1 1-4.5 4.5" }], ["path", { "d": "M12 7.5V9" }], ["path", { "d": "M7.5 12H9" }], ["path", { "d": "M16.5 12H15" }], ["path", { "d": "M12 16.5V15" }], ["path", { "d": "m8 8 1.88 1.88" }], ["path", { "d": "M14.12 9.88 16 8" }], ["path", { "d": "m8 16 1.88-1.88" }], ["path", { "d": "M14.12 14.12 16 16" }]], "Music2": [["circle", { "cx": "8", "cy": "18", "r": "4" }], ["path", { "d": "M12 18V2l7 4" }]], "Cloud": [["path", { "d": "M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z" }]], "Cat": [["path", { "d": "M12 5c.67 0 1.35.09 2 .26 1.78-2 5.03-2.84 6.42-2.26 1.4.58-.42 7-.42 7 .57 1.07 1 2.24 1 3.44C21 17.9 16.97 21 12 21s-9-3-9-7.56c0-1.25.5-2.4 1-3.44 0 0-1.89-6.42-.5-7 1.39-.58 4.72.23 6.5 2.23A9.04 9.04 0 0 1 12 5Z" }], ["path", { "d": "M8 14v.5" }], ["path", { "d": "M16 14v.5" }], ["path", { "d": "M11.25 16.25h1.5L12 17l-.75-.75Z" }]], "Moon": [["path", { "d": "M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803a6 6 0 0 0 8.268 8.268c.344-.215.825-.004.803.401" }]], "Heart": [["path", { "d": "M2 9.5a5.5 5.5 0 0 1 9.591-3.676.56.56 0 0 0 .818 0A5.49 5.49 0 0 1 22 9.5c0 2.29-1.5 4-3 5.5l-5.492 5.313a2 2 0 0 1-3 .019L5 15c-1.5-1.5-3-3.2-3-5.5" }]] };
var resolveLucideIconNode = (name) => icons[name] ?? null;
var resolveLucideIconNames = (names) => Array.isArray(names) ? names.filter((n) => icons[n]) : [];

// folia:src/components/visualizer/lumiere/lineart/iconPaths.ts
var ICON_VIEWBOX = 24;
var CIRCLE_STEPS = 48;
var CURVE_STEPS = 12;
var num = (value, fallback = 0) => {
  const parsed = typeof value === "number" ? value : Number.parseFloat(String(value ?? ""));
  return Number.isFinite(parsed) ? parsed : fallback;
};
var ellipsePoints = (cx, cy, rx, ry, steps = CIRCLE_STEPS) => Array.from({ length: steps + 1 }, (_, i) => {
  const a = i / steps * Math.PI * 2;
  return [cx + Math.cos(a) * rx, cy + Math.sin(a) * ry];
});
var rectPoints = (x, y, w, h, rxIn, ryIn) => {
  const rx = Math.min(Math.max(0, rxIn), w / 2);
  const ry = Math.min(Math.max(0, ryIn), h / 2);
  if (rx <= 0 || ry <= 0) return [[x, y], [x + w, y], [x + w, y + h], [x, y + h], [x, y]];
  const corner = (cx, cy, from) => Array.from({ length: 7 }, (_, i) => {
    const a = from + i / 6 * (Math.PI / 2);
    return [cx + Math.cos(a) * rx, cy + Math.sin(a) * ry];
  });
  const points = [
    ...corner(x + w - rx, y + ry, -Math.PI / 2),
    ...corner(x + w - rx, y + h - ry, 0),
    ...corner(x + rx, y + h - ry, Math.PI / 2),
    ...corner(x + rx, y + ry, Math.PI)
  ];
  points.push(points[0]);
  return points;
};
var pointList = (value) => {
  const numbers = String(value ?? "").trim().split(/[\s,]+/).map(Number).filter(Number.isFinite);
  const points = [];
  for (let i = 0; i + 1 < numbers.length; i += 2) points.push([numbers[i], numbers[i + 1]]);
  return points;
};
var arcToPoints = (from, rxIn, ryIn, angleDeg, largeArc, sweep, to) => {
  let rx = Math.abs(rxIn);
  let ry = Math.abs(ryIn);
  if (rx === 0 || ry === 0 || from[0] === to[0] && from[1] === to[1]) return [to];
  const phi = angleDeg * Math.PI / 180;
  const cos = Math.cos(phi);
  const sin = Math.sin(phi);
  const dx = (from[0] - to[0]) / 2;
  const dy = (from[1] - to[1]) / 2;
  const x1 = cos * dx + sin * dy;
  const y1 = -sin * dx + cos * dy;
  const lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry);
  if (lambda > 1) {
    rx *= Math.sqrt(lambda);
    ry *= Math.sqrt(lambda);
  }
  const numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1;
  const denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1;
  const factor = (largeArc === sweep ? -1 : 1) * Math.sqrt(Math.max(0, numerator / Math.max(denominator, 1e-12)));
  const cx1 = factor * rx * y1 / ry;
  const cy1 = -factor * ry * x1 / rx;
  const cx = cos * cx1 - sin * cy1 + (from[0] + to[0]) / 2;
  const cy = sin * cx1 + cos * cy1 + (from[1] + to[1]) / 2;
  const angleOf = (ux, uy) => Math.atan2(uy, ux);
  const start = angleOf((x1 - cx1) / rx, (y1 - cy1) / ry);
  let delta = angleOf((-x1 - cx1) / rx, (-y1 - cy1) / ry) - start;
  if (sweep && delta < 0) delta += Math.PI * 2;
  if (!sweep && delta > 0) delta -= Math.PI * 2;
  const steps = Math.max(2, Math.ceil(Math.abs(delta) / (Math.PI * 2) * CIRCLE_STEPS));
  const points = [];
  for (let i = 1; i <= steps; i += 1) {
    const a = start + delta * i / steps;
    const ex = Math.cos(a) * rx;
    const ey = Math.sin(a) * ry;
    points.push(i === steps ? to : [cos * ex - sin * ey + cx, sin * ex + cos * ey + cy]);
  }
  return points;
};
var cubicTo = (p0, p1, p2, p3) => Array.from({ length: CURVE_STEPS }, (_, k) => {
  const t = (k + 1) / CURVE_STEPS;
  const u = 1 - t;
  const a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
  return [a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]];
});
var quadTo = (p0, p1, p2) => Array.from({ length: CURVE_STEPS }, (_, k) => {
  const t = (k + 1) / CURVE_STEPS;
  const u = 1 - t;
  return [u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]];
});
var svgPathToPolylines = (d) => {
  const result = [];
  let index = 0;
  const skip = () => {
    while (index < d.length && /[\s,]/.test(d[index])) index += 1;
  };
  const readNumber = () => {
    skip();
    const match = /^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/.exec(d.slice(index));
    if (!match) return null;
    index += match[0].length;
    return Number(match[0]);
  };
  const readFlag = () => {
    skip();
    const char = d[index];
    if (char !== "0" && char !== "1") return null;
    index += 1;
    return char === "1";
  };
  const hasNumber = () => {
    skip();
    return index < d.length && /[+\-.\d]/.test(d[index]);
  };
  let current = [0, 0];
  let start = [0, 0];
  let points = [];
  let lastControl = null;
  let lastKind = "";
  const flush = (closed) => {
    if (points.length > 1) result.push({ points, closed });
    points = [];
  };
  while (index < d.length) {
    skip();
    if (index >= d.length) break;
    const command = d[index];
    if (!/[MmLlHhVvCcSsQqTtAaZz]/.test(command)) break;
    index += 1;
    const relative = command === command.toLowerCase();
    const kind = command.toUpperCase();
    const abs = (x, y) => relative ? [current[0] + x, current[1] + y] : [x, y];
    if (kind === "Z") {
      if (points.length > 0) {
        points.push(start);
        flush(true);
      }
      current = start;
      lastControl = null;
      lastKind = kind;
      continue;
    }
    let first = true;
    do {
      if (kind === "M") {
        const x = readNumber();
        const y = readNumber();
        if (x === null || y === null) break;
        const target = abs(x, y);
        if (first) {
          flush(false);
          start = target;
          points = [target];
        } else {
          points.push(target);
        }
        current = target;
        lastControl = null;
      } else if (kind === "L") {
        const x = readNumber();
        const y = readNumber();
        if (x === null || y === null) break;
        current = abs(x, y);
        points.push(current);
        lastControl = null;
      } else if (kind === "H") {
        const x = readNumber();
        if (x === null) break;
        current = [relative ? current[0] + x : x, current[1]];
        points.push(current);
        lastControl = null;
      } else if (kind === "V") {
        const y = readNumber();
        if (y === null) break;
        current = [current[0], relative ? current[1] + y : y];
        points.push(current);
        lastControl = null;
      } else if (kind === "C" || kind === "S") {
        let c1;
        if (kind === "C") {
          const x1 = readNumber();
          const y1 = readNumber();
          if (x1 === null || y1 === null) break;
          c1 = abs(x1, y1);
        } else {
          c1 = lastControl && (lastKind === "C" || lastKind === "S") ? [current[0] * 2 - lastControl[0], current[1] * 2 - lastControl[1]] : current;
        }
        const x2 = readNumber();
        const y2 = readNumber();
        const x = readNumber();
        const y = readNumber();
        if (x2 === null || y2 === null || x === null || y === null) break;
        const c2 = abs(x2, y2);
        const end = abs(x, y);
        if (points.length === 0) points = [current];
        points.push(...cubicTo(current, c1, c2, end));
        current = end;
        lastControl = c2;
      } else if (kind === "Q" || kind === "T") {
        let c;
        if (kind === "Q") {
          const x1 = readNumber();
          const y1 = readNumber();
          if (x1 === null || y1 === null) break;
          c = abs(x1, y1);
        } else {
          c = lastControl && (lastKind === "Q" || lastKind === "T") ? [current[0] * 2 - lastControl[0], current[1] * 2 - lastControl[1]] : current;
        }
        const x = readNumber();
        const y = readNumber();
        if (x === null || y === null) break;
        const end = abs(x, y);
        if (points.length === 0) points = [current];
        points.push(...quadTo(current, c, end));
        current = end;
        lastControl = c;
      } else if (kind === "A") {
        const rx = readNumber();
        const ry = readNumber();
        const angle = readNumber();
        const large = readFlag();
        const sweep = readFlag();
        const x = readNumber();
        const y = readNumber();
        if (rx === null || ry === null || angle === null || large === null || sweep === null || x === null || y === null) break;
        const end = abs(x, y);
        if (points.length === 0) points = [current];
        points.push(...arcToPoints(current, rx, ry, angle, large, sweep, end));
        current = end;
        lastControl = null;
      }
      lastKind = kind;
      first = false;
    } while (hasNumber());
  }
  flush(false);
  return result;
};
var nodeToPolylines = (tag, attrs) => {
  switch (tag) {
    case "path":
      return svgPathToPolylines(String(attrs.d ?? ""));
    case "circle": {
      const r = num(attrs.r);
      return r > 0 ? [{ points: ellipsePoints(num(attrs.cx), num(attrs.cy), r, r), closed: true }] : [];
    }
    case "ellipse": {
      const rx = num(attrs.rx);
      const ry = num(attrs.ry);
      return rx > 0 && ry > 0 ? [{ points: ellipsePoints(num(attrs.cx), num(attrs.cy), rx, ry), closed: true }] : [];
    }
    case "line":
      return [{ points: [[num(attrs.x1), num(attrs.y1)], [num(attrs.x2), num(attrs.y2)]], closed: false }];
    case "rect": {
      const w = num(attrs.width);
      const h = num(attrs.height);
      if (w <= 0 || h <= 0) return [];
      const rx = attrs.rx !== void 0 ? num(attrs.rx) : num(attrs.ry);
      const ry = attrs.ry !== void 0 ? num(attrs.ry) : rx;
      return [{ points: rectPoints(num(attrs.x), num(attrs.y), w, h, rx, ry), closed: true }];
    }
    case "polyline":
    case "polygon": {
      const points = pointList(attrs.points);
      if (tag === "polygon" && points.length > 2) points.push(points[0]);
      return points.length > 1 ? [{ points, closed: tag === "polygon" }] : [];
    }
    default:
      return [];
  }
};
var iconNodeToPolylines = (node2) => node2.flatMap((entry) => {
  const [tag, attrs, children] = entry;
  return [
    ...nodeToPolylines(tag, attrs),
    ...Array.isArray(children) ? iconNodeToPolylines(children) : []
  ];
});
var cache = /* @__PURE__ */ new Map();
var lucideIconPolylines = (name) => {
  if (cache.has(name)) return cache.get(name);
  const node2 = resolveLucideIconNode(name);
  if (!node2) return null;
  const polylines = iconNodeToPolylines(node2).filter((polyline) => polyline.points.length > 1);
  const value = polylines.length > 0 ? polylines : null;
  cache.set(name, value);
  return value;
};

// folia:src/components/visualizer/lumiere/lineart/themeIcons.ts
var lumiereScaleMask9 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET9 = (1593667296 ^ lumiereScaleMask9) + Math.imul(445441147 ^ lumiereScaleMask9, 1354289308 ^ lumiereScaleMask9) - ((1593667296 ^ lumiereScaleMask9) + Math.imul(445441147 ^ lumiereScaleMask9, 1354289308 ^ lumiereScaleMask9));
var ICON_SIZE = [0.085, 0.13];
var TEXT_PAD = 0.05 + LUMIERE_NEUTRAL_OFFSET9;
var EDGE = 0.05;
var ATTEMPTS = 48;
var overlapsRegion = (cx, cy, half, region, pad) => Math.abs(cx - region.cx) < half + region.w / 2 + pad && Math.abs(cy - region.cy) < half + region.h / 2 + pad;
var placeThemeIcons = (options) => {
  const names = options.names.filter((name) => lucideIconPolylines(name) !== null);
  if (names.length === 0) return [];
  const { aspect, avoid, random } = options;
  const count = options.count ?? 2 + (random() < 0.5 ? 1 : 0);
  const offset = options.offset ?? 0;
  const placed = [];
  for (let i = 0; i < count; i += 1) {
    const name = names[(offset + i) % names.length];
    const size = ICON_SIZE[0] + random() * (ICON_SIZE[1] - ICON_SIZE[0]);
    const rotation = (random() - 0.5) * 0.3;
    const half = size * 0.72;
    for (let attempt = 0; attempt < ATTEMPTS; attempt += 1) {
      const cx = EDGE + half + random() * Math.max(0, aspect - 2 * (EDGE + half));
      const cy = EDGE + half + random() * Math.max(0, 1 - 2 * (EDGE + half));
      if (overlapsRegion(cx, cy, half, avoid, TEXT_PAD)) continue;
      if (placed.some((other) => Math.hypot(other.cx - cx, other.cy - cy) < (other.size + size) * 0.9)) continue;
      placed.push({ name, cx, cy, size, rotation });
      break;
    }
  }
  return placed;
};
var transformPolyline = (polyline, icon) => {
  const scale = icon.size / ICON_VIEWBOX;
  const cos = Math.cos(icon.rotation);
  const sin = Math.sin(icon.rotation);
  const half = ICON_VIEWBOX / 2;
  return polyline.points.map(([x, y]) => {
    const lx = (x - half) * scale;
    const ly = (y - half) * scale;
    return [icon.cx + lx * cos - ly * sin, icon.cy + lx * sin + ly * cos];
  });
};
var polylineLength = (points) => {
  let length = 0;
  for (let i = 1; i < points.length; i += 1) length += Math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]);
  return length;
};
var themeIconsArt = (icons2, random, delay = 0.18, alpha = 0.5) => {
  const paths = [];
  const nodes = [];
  icons2.forEach((icon, iconIndex) => {
    const polylines = lucideIconPolylines(icon.name);
    if (!polylines) return;
    const start = delay + iconIndex * 0.12;
    const strokes = polylines.map((polyline) => transformPolyline(polyline, icon));
    strokes.forEach((points, strokeIndex) => {
      paths.push({
        points,
        width: 13e-4,
        alpha,
        delay: start + Math.min(strokeIndex, 8) * 0.035,
        span: 0.32
      });
    });
    const longest = strokes.reduce((best, points, index) => polylineLength(points) > polylineLength(strokes[best]) ? index : best, 0);
    nodes.push({ at: strokes[longest][0], size: 0.02, delay: start + 0.08, twinklePhase: random() * Math.PI * 2 });
    const other = strokes[Math.floor(random() * strokes.length)];
    if (strokes.length > 1) {
      nodes.push({ at: other[other.length - 1], size: 0.015, delay: start + 0.3, twinklePhase: random() * Math.PI * 2 });
    }
  });
  return { paths, nodes };
};
var buildThemeIconArt = (options) => {
  const icons2 = placeThemeIcons(options);
  return themeIconsArt(icons2, options.random, options.delay, options.alpha);
};
var buildShotIconArts = (options) => {
  if (!options.enabled) return [];
  const names = resolveLucideIconNames(options.icons).filter((name) => lucideIconPolylines(name) !== null);
  if (names.length === 0) return [];
  return options.shotKinds.map((kind, index) => buildThemeIconArt({
    names,
    aspect: options.aspect,
    avoid: options.avoid,
    random: createRng(`${options.seed}:${index}:${kind}:icons`),
    offset: index * 2
  }));
};

// folia:src/utils/lyrics/graphemeTiming.ts
var graphemeSegmenter = typeof Intl !== "undefined" && Intl.Segmenter ? new Intl.Segmenter(void 0, { granularity: "grapheme" }) : null;
var splitLyricGraphemes = (text) => {
  if (!text) {
    return [];
  }
  if (graphemeSegmenter) {
    return Array.from(graphemeSegmenter.segment(text), ({ segment: segment2 }) => segment2);
  }
  return Array.from(text);
};
var buildEvenGraphemeTimings = (text, startTime, endTime, wordIndex) => {
  const graphemes = splitLyricGraphemes(text);
  if (graphemes.length === 0) {
    return [];
  }
  const duration = Math.max(endTime - startTime, 0);
  const unitDuration = duration / graphemes.length;
  return graphemes.map((char, index) => ({
    char,
    startTime: startTime + unitDuration * index,
    endTime: index === graphemes.length - 1 ? endTime : startTime + unitDuration * (index + 1),
    ...typeof wordIndex === "number" ? { wordIndex } : {}
  }));
};
var buildWordGraphemeTimings = (word, wordIndex) => {
  if (!word.syllables?.length) {
    return buildEvenGraphemeTimings(word.text, word.startTime, word.endTime, wordIndex);
  }
  return word.syllables.flatMap(
    (syllable) => buildEvenGraphemeTimings(syllable.text, syllable.startTime, syllable.endTime, wordIndex)
  );
};
var findGraphemeSequence = (source, target, fromIndex) => {
  if (target.length === 0) {
    return fromIndex;
  }
  for (let index = fromIndex; index <= source.length - target.length; index += 1) {
    let matched = true;
    for (let targetIndex = 0; targetIndex < target.length; targetIndex += 1) {
      if (source[index + targetIndex] !== target[targetIndex]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      return index;
    }
  }
  return -1;
};
var buildLineGraphemeTimeline = (line2) => {
  const lineGraphemes = splitLyricGraphemes(line2.fullText);
  if (lineGraphemes.length === 0) {
    return [];
  }
  if (line2.words.length === 0) {
    return buildEvenGraphemeTimings(line2.fullText, line2.startTime, line2.endTime);
  }
  const timeline = [];
  let cursor = 0;
  let lastResolvedTime = line2.startTime;
  line2.words.forEach((word, wordIndex) => {
    const wordGraphemes = splitLyricGraphemes(word.text);
    if (wordGraphemes.length === 0) {
      return;
    }
    const matchedStart = findGraphemeSequence(lineGraphemes, wordGraphemes, cursor);
    const start = matchedStart >= 0 ? matchedStart : cursor;
    const end = Math.min(start + wordGraphemes.length, lineGraphemes.length);
    for (let gapIndex = cursor; gapIndex < start; gapIndex += 1) {
      timeline[gapIndex] = {
        char: lineGraphemes[gapIndex],
        startTime: word.startTime,
        endTime: word.startTime
      };
    }
    const wordTimings = buildWordGraphemeTimings(word, wordIndex);
    for (let localIndex = 0; localIndex < end - start; localIndex += 1) {
      const timing = wordTimings[localIndex] ?? buildEvenGraphemeTimings(
        wordGraphemes[localIndex] ?? "",
        word.startTime,
        word.endTime,
        wordIndex
      )[0];
      if (!timing) {
        continue;
      }
      timeline[start + localIndex] = {
        ...timing,
        char: lineGraphemes[start + localIndex]
      };
      lastResolvedTime = Math.max(lastResolvedTime, timing.endTime);
    }
    cursor = Math.max(cursor, end);
  });
  for (let index = 0; index < lineGraphemes.length; index += 1) {
    if (timeline[index]) {
      continue;
    }
    timeline[index] = {
      char: lineGraphemes[index],
      startTime: lastResolvedTime,
      endTime: lastResolvedTime
    };
  }
  return timeline;
};

// folia:src/components/visualizer/wordColoring.ts
var CJK_REGEX = /[\u4e00-\u9fa5\u3040-\u30ff\uac00-\ud7af]/;
var isCJK = (text) => CJK_REGEX.test(text);
var normalizeWordColorToken = (text) => text.toLowerCase().replace(/[^\w]/g, "");
var resolveWordColorEntryText = (entry) => {
  if (!entry || typeof entry !== "object" || !("word" in entry)) {
    return "";
  }
  const word = entry.word;
  return typeof word === "string" ? word.trim() : "";
};
var resolveWordColorEntryColor = (entry) => {
  if (!entry || typeof entry !== "object" || !("color" in entry)) {
    return "";
  }
  const color = entry.color;
  return typeof color === "string" ? color : "";
};
var rangesOverlap = (a, b) => a.startOffset < b.endOffset && b.startOffset < a.endOffset;
var selectNonOverlappingRanges = (ranges) => {
  const selected = [];
  const prioritySorted = [...ranges].sort((a, b) => b.priority - a.priority || a.startOffset - b.startOffset || a.endOffset - b.endOffset);
  prioritySorted.forEach((range) => {
    if (!selected.some((current) => rangesOverlap(current, range))) {
      selected.push(range);
    }
  });
  return selected.sort((a, b) => a.startOffset - b.startOffset || a.endOffset - b.endOffset);
};
var prepareWordColorMatchers = (wordColors, keywordColoringEnabled = true) => {
  if (!keywordColoringEnabled || !wordColors || wordColors.length === 0) {
    return [];
  }
  return wordColors.flatMap((entry) => {
    const target = resolveWordColorEntryText(entry);
    if (!target) {
      return [];
    }
    const color = resolveWordColorEntryColor(entry);
    if (!color) {
      return [];
    }
    if (isCJK(target)) {
      return [{
        color,
        cjkPhrases: [target],
        englishWords: [],
        priority: target.length
      }];
    }
    const englishWords = target.split(/\s+/).map(normalizeWordColorToken).filter(Boolean);
    if (englishWords.length === 0) {
      return [];
    }
    return [{
      color,
      cjkPhrases: [],
      englishWords,
      priority: Math.max(...englishWords.map((word) => word.length))
    }];
  });
};
var buildWordColorRangesFromMatchers = (lineText, matchers) => {
  if (!lineText || matchers.length === 0) {
    return [];
  }
  const ranges = [];
  const englishColorByWord = /* @__PURE__ */ new Map();
  matchers.forEach((matcher) => {
    matcher.cjkPhrases.forEach((target) => {
      let cursor = 0;
      while (cursor < lineText.length) {
        const startOffset = lineText.indexOf(target, cursor);
        if (startOffset < 0) {
          break;
        }
        ranges.push({
          startOffset,
          endOffset: startOffset + target.length,
          color: matcher.color,
          priority: matcher.priority
        });
        cursor = startOffset + Math.max(target.length, 1);
      }
    });
    matcher.englishWords.forEach((word) => {
      const current = englishColorByWord.get(word);
      if (!current || matcher.priority > current.priority) {
        englishColorByWord.set(word, { color: matcher.color, priority: matcher.priority });
      }
    });
  });
  if (englishColorByWord.size > 0) {
    const wordRegex = /\w+/g;
    let match;
    while ((match = wordRegex.exec(lineText)) !== null) {
      const wordColor = englishColorByWord.get(normalizeWordColorToken(match[0]));
      if (wordColor) {
        ranges.push({
          startOffset: match.index,
          endOffset: match.index + match[0].length,
          color: wordColor.color,
          priority: wordColor.priority
        });
      }
    }
  }
  return selectNonOverlappingRanges(ranges);
};
var resolveTokenColorMap = (tokens, ranges) => {
  const colors = /* @__PURE__ */ new Map();
  let rangeIndex = 0;
  tokens.forEach((token) => {
    if (!token.timed) {
      return;
    }
    while (rangeIndex < ranges.length && ranges[rangeIndex].endOffset <= token.startOffset) {
      rangeIndex += 1;
    }
    const range = ranges[rangeIndex];
    if (range && rangesOverlap(range, token)) {
      colors.set(token.key, range.color);
    }
  });
  return colors;
};

// folia:src/components/visualizer/lumiere/text/keywordColors.ts
var KEYWORD_MIX = {
  glyph: 0.6,
  halo: 0.75,
  star: 0.55,
  burst: 0.7,
  echo: 0.3
};
var KEYWORD_STAR_WHITE = 0.35;
var KEYWORD_HALO_GAIN = 1.25;
var prepareLumiereKeywords = (wordColors, enabled) => prepareWordColorMatchers(wordColors, enabled);
var parseRgb = (color) => {
  const channels = parseColorChannels(color);
  return channels ? [channels.r / 255, channels.g / 255, channels.b / 255] : null;
};
var resolveGlyphKeywordColors = (text, matchers) => {
  const graphemes = splitLyricGraphemes(text);
  const colors = graphemes.map(() => null);
  if (matchers.length === 0 || graphemes.length === 0) return colors;
  const ranges = buildWordColorRangesFromMatchers(text, [...matchers]);
  if (ranges.length === 0) return colors;
  let offset = 0;
  const tokens = graphemes.map((grapheme, index) => {
    const token = { key: String(index), timed: grapheme.trim().length > 0, startOffset: offset, endOffset: offset + grapheme.length };
    offset += grapheme.length;
    return token;
  });
  const parsed = /* @__PURE__ */ new Map();
  resolveTokenColorMap(tokens, ranges).forEach((hex, key) => {
    if (!parsed.has(hex)) parsed.set(hex, parseRgb(hex));
    colors[Number(key)] = parsed.get(hex) ?? null;
  });
  return colors;
};
var keywordLight = (light, keyword, amount) => {
  const keywordPeak = Math.max(keyword[0], keyword[1], keyword[2]);
  const hue = keywordPeak > 1e-4 ? scaleRgb(keyword, 1 / keywordPeak) : WHITE;
  const mixed = mixRgb(light, hue, amount);
  const peak = Math.max(mixed[0], mixed[1], mixed[2]);
  const target = Math.max(light[0], light[1], light[2]);
  return peak > 1e-4 ? scaleRgb(mixed, target / peak) : light;
};
var keywordTints = (light, keyword) => ({
  glyph: keywordLight(light, keyword, KEYWORD_MIX.glyph),
  halo: hexOf(keywordLight(light, keyword, KEYWORD_MIX.halo)),
  star: hexOf(mixRgb(keywordLight(light, keyword, KEYWORD_MIX.star), WHITE, KEYWORD_STAR_WHITE))
});
var keywordBurstColor = (burstColor, light, keyword) => mixRgb(burstColor, keywordLight(light, keyword, KEYWORD_MIX.burst), 0.8);
var keywordEchoColor = (light, keyword) => keywordLight(light, keyword, KEYWORD_MIX.echo);

// folia:src/components/visualizer/lumiere/text/glyphLine.ts
var lumiereScaleMask10 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET10 = (3848464964 ^ lumiereScaleMask10) + Math.imul(523 ^ lumiereScaleMask10, 979 ^ lumiereScaleMask10) - ((3848464964 ^ lumiereScaleMask10) + Math.imul(523 ^ lumiereScaleMask10, 979 ^ lumiereScaleMask10));
var UPRIGHT = /[ᄀ-ᇿ⺀-⿿　-〿぀-ヿ㄀-ㇿ㈀-鿿가-힯豈-﫿︰-﹏＀-￯]|[\u{20000}-\u{3134f}]/u;
var glyphFont = (weight, px, family2) => `${weight} ${px}px ${family2}`;
var isUprightGlyph = (char) => UPRIGHT.test(char);
var buildGlyphLine = (pixi, options) => {
  const { text, fontPx } = options;
  const graphemes = splitLyricGraphemes(text);
  const canvas = document.createElement("canvas");
  const context = canvas.getContext("2d");
  const fontSpec = glyphFont(options.weight, fontPx, options.font);
  context.font = fontSpec;
  const spacing = (options.letterSpacing ?? 0) * fontPx;
  const offsets = [0];
  let prefix = "";
  graphemes.forEach((char, index) => {
    prefix += char;
    offsets.push(context.measureText(prefix).width + spacing * (index + 1));
  });
  const width = Math.max(1, offsets[offsets.length - 1]);
  const height = Math.ceil(fontPx * 1.5);
  const pad = Math.ceil(fontPx * 0.25);
  const limit = options.maxCanvasPx ?? 8192 + LUMIERE_NEUTRAL_OFFSET10;
  const resolution = Math.min(options.resolution, limit / (width + pad * 2), limit / (height + pad * 2));
  canvas.width = Math.ceil((width + pad * 2) * resolution);
  canvas.height = Math.ceil((height + pad * 2) * resolution);
  context.setTransform(resolution, 0, 0, resolution, 0, 0);
  context.font = fontSpec;
  context.textBaseline = "middle";
  context.fillStyle = "#ffffff";
  context.strokeStyle = "#ffffff";
  const draw = (char, x) => {
    if (options.outline) {
      context.globalAlpha = 0.14;
      context.fillText(char, x, pad + height / 2);
      context.globalAlpha = 1;
      context.lineWidth = fontPx * options.outline;
      context.strokeText(char, x, pad + height / 2);
    } else {
      context.fillText(char, x, pad + height / 2);
    }
  };
  if (spacing === 0) {
    draw(text, pad);
  } else {
    graphemes.forEach((char, index) => draw(char, pad + offsets[index]));
  }
  const source = new pixi.CanvasSource({ resource: canvas, resolution: 1, autoGarbageCollect: true });
  source.resolution = resolution;
  const base = new pixi.Texture({ source });
  const glyphs = graphemes.map((char, index) => {
    const x = offsets[index];
    const w = Math.max(0.5, offsets[index + 1] - x);
    const left = index === 0 ? 0 : pad + x;
    const right = index === graphemes.length - 1 ? width + pad * 2 : pad + x + w;
    const frame2 = new pixi.Rectangle(left, 0, right - left, height + pad * 2);
    return {
      char,
      x: left - pad,
      width: right - left,
      charX: x,
      charWidth: w,
      anchorX: (pad + x + w / 2 - left) / (right - left),
      anchorY: 0.5,
      texture: new pixi.Texture({ source, frame: frame2 }),
      blank: char.trim().length === 0,
      upright: isUprightGlyph(char)
    };
  });
  return {
    text,
    fontPx,
    width,
    height,
    glyphs,
    destroy: () => {
      glyphs.forEach((glyph) => glyph.texture.destroy(false));
      base.destroy(true);
    }
  };
};

// folia:src/components/visualizer/lumiere/text/reveal.ts
var buildGlyphTimings = (line2) => buildLineGraphemeTimeline(line2).map((timing) => ({ start: timing.startTime, end: timing.endTime }));
var clamp014 = (value) => Math.min(1, Math.max(0, value));
var glyphProgress = (timing, time) => clamp014((time - timing.start) / Math.max(timing.end - timing.start, 0.08));
var flashEnvelope = (timing, time, decay = 0.5, attack = 0.15) => {
  const age = time - timing.start;
  if (age <= 0) return 0;
  if (age < attack) {
    const t = age / attack;
    return t * t * (3 - 2 * t);
  }
  return Math.exp(-(age - attack) / decay);
};

// folia:src/utils/lyrics/wordSegmentation.ts
var PUNCTUATION_ONLY = /^[\s\p{P}\p{S}]+$/u;
var isWordLikeText = (text) => !PUNCTUATION_ONLY.test(text);
var segmentsFromBoundaries = (boundaries) => {
  let cursor = 0;
  return boundaries.map((segment2) => {
    const part = { segment: segment2, index: cursor, isWordLike: isWordLikeText(segment2) };
    cursor += segment2.length;
    return part;
  });
};
var segmentTextWords = (text) => {
  if (!text) {
    return [];
  }
  const Segmenter = typeof Intl !== "undefined" ? Intl.Segmenter : void 0;
  if (Segmenter) {
    try {
      return Array.from(new Segmenter(void 0, { granularity: "word" }).segment(text), (part) => ({
        segment: part.segment,
        index: part.index,
        isWordLike: part.isWordLike ?? isWordLikeText(part.segment)
      }));
    } catch {
    }
  }
  return segmentsFromBoundaries(splitLyricGraphemes(text));
};
var isValidWordSegmentation = (text, boundaries) => Array.isArray(boundaries) && boundaries.length > 0 && boundaries.every((segment2) => typeof segment2 === "string") && boundaries.join("") === text;
var EDGE_WHITESPACE = /^(\s*)(.*?)(\s*)$/su;
var splitEdgeWhitespace = (boundaries) => boundaries.flatMap((boundary) => {
  const [, lead, core, trail] = EDGE_WHITESPACE.exec(boundary) ?? [];
  return core ? [lead, core, trail].filter(Boolean) : [boundary].filter(Boolean);
});
var segmentLyricWords = (line2) => {
  if (isValidWordSegmentation(line2.fullText, line2.wordSegments)) {
    return segmentsFromBoundaries(splitEdgeWhitespace(line2.wordSegments));
  }
  if (isValidWordSegmentation(line2.fullText, line2.autoWordSegments)) {
    return segmentsFromBoundaries(line2.autoWordSegments);
  }
  return segmentTextWords(line2.fullText);
};

// folia:src/components/visualizer/lumiere/text/wordStyle.ts
var lumiereScaleMask11 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET11 = (4034148709 ^ lumiereScaleMask11) + Math.imul(699505802 ^ lumiereScaleMask11, 2401607263 ^ lumiereScaleMask11) - ((4034148709 ^ lumiereScaleMask11) + Math.imul(699505802 ^ lumiereScaleMask11, 2401607263 ^ lumiereScaleMask11));
var MAX_WORD_SCALE = 1.5 + LUMIERE_NEUTRAL_OFFSET11;
var segmentWords = (line2) => {
  const pieces = segmentLyricWords(line2);
  const words = [];
  let cursor = 0;
  for (const { segment: segment2, isWordLike } of pieces) {
    const length = splitLyricGraphemes(segment2).length;
    if (length === 0) continue;
    words.push({ text: segment2, start: cursor, end: cursor + length, blank: !isWordLike });
    cursor += length;
  }
  return words;
};
var FUNCTION_WORDS = new Set(Array.from("\u7684\u4E86\u5728\u628A\u662F\u6211\u4F60\u4ED6\u5979\u5B83\u4EEC\u548C\u4E0E\u4E5F\u5C31\u90FD\u7740\u8FC7\u5417\u5462\u5427\u554A\u5440\u54E6\u88AB\u8BA9\u7ED9\u4ECE\u5411\u5230\u8FD9\u90A3\u4E4B\u800C\u53C8\u5F88"));
var MINOR_LATIN = /* @__PURE__ */ new Set(["a", "an", "the", "of", "to", "in", "on", "at", "me", "my", "with", "and", "or", "is", "i", "you", "it", "by", "for"]);
var wordScales = (words, seed) => {
  const rng = createRng(`${seed}:words`);
  const lengthOf = (word) => word.end - word.start;
  const minor = (word) => word.blank || lengthOf(word) === 1 && FUNCTION_WORDS.has(word.text) || MINOR_LATIN.has(word.text.toLowerCase());
  let key = -1;
  words.forEach((word, index) => {
    if (minor(word)) return;
    if (key < 0 || lengthOf(word) >= lengthOf(words[key])) key = index;
  });
  return words.map((word, index) => {
    const jitter = rng();
    if (word.blank && word.text.trim().length === 0) return 1;
    if (index === key && words.length > 1) return 1.45;
    if (minor(word)) return 0.62;
    return 0.85 + jitter * 0.35;
  });
};
var wordJags = (words, scales, seed) => {
  const rng = createRng(`${seed}:jags`);
  const keyScale = Math.max(...scales);
  return words.map((_, index) => {
    const offset = (rng() - 0.5) * 2;
    const scale = scales[index] ?? 1;
    if (scale === keyScale && words.length > 1) return 0;
    return offset * (scale < 0.7 ? 0.32 : 0.2);
  });
};

// folia:src/components/visualizer/lumiere/text/lyricEcho.ts
var LIFE = 7;
var SPEED = 0.075;
var BIRTH_DISTANCE = 0.08;
var PREPARE = 3;
var clamp015 = (value) => Math.min(1, Math.max(0, value));
var smooth = (value) => {
  const t = clamp015(value);
  return t * t * (3 - 2 * t);
};
var createLyricEcho = (pixi, options) => {
  const { height } = options;
  const rng = createRng(`${options.seed}:echo`);
  const view = new pixi.Container();
  const fontPx = options.size * height;
  const resolution = Math.min(options.resolution, 1.5);
  const fragments = [];
  const holders = [];
  const echoLines = [];
  options.lines.forEach((line2) => {
    const graphemes = splitLyricGraphemes(line2.fullText);
    const timings = buildGlyphTimings(line2);
    const keywordColors = options.keywords && options.keywords.length > 0 ? resolveGlyphKeywordColors(line2.fullText, options.keywords) : null;
    const first = fragments.length;
    segmentWords(line2).forEach((word) => {
      if (word.blank) return;
      const end = Math.min(word.end, graphemes.length);
      if (end <= word.start) return;
      const holder = new pixi.Container();
      view.addChild(holder);
      holders.push(holder);
      fragments.push({
        birth: timings[word.start]?.start ?? line2.startTime,
        across: (rng() - 0.5) * 2.8,
        speed: 0.7 + rng() * 0.7,
        scale: 0.4 + rng() * 0.6,
        rotation: (rng() - 0.5) * 0.9,
        stretch: 0.75 + rng() * 0.7,
        shear: (rng() - 0.5) * 0.12,
        spin: (rng() - 0.5) * 0.08,
        start: word.start,
        end,
        glyphs: graphemes.slice(word.start, end).map((char, offsetInWord) => {
          const angle = rng() * Math.PI * 2;
          return {
            sprite: null,
            blank: char.trim().length === 0,
            offset: 0,
            dx: Math.cos(angle),
            dy: Math.sin(angle),
            speed: 0.3 + rng() * 0.9,
            spin: (rng() - 0.5) * 0.5,
            keyword: keywordColors?.[word.start + offsetInWord] ?? null
          };
        })
      });
    });
    const births = fragments.slice(first).map((fragment2) => fragment2.birth);
    if (births.length === 0) return;
    echoLines.push({
      text: line2.fullText,
      first,
      last: fragments.length,
      from: Math.min(...births),
      to: Math.max(...births),
      layout: null
    });
  });
  const rasterize = (echoLine) => {
    const layout = buildGlyphLine(pixi, {
      text: echoLine.text,
      fontPx,
      font: options.font,
      weight: options.weight,
      resolution,
      letterSpacing: 0.04,
      outline: 0.012,
      maxCanvasPx: 4096
    });
    echoLine.layout = layout;
    for (let index = echoLine.first; index < echoLine.last; index += 1) {
      const fragment2 = fragments[index];
      const slices = layout.glyphs.slice(fragment2.start, fragment2.end);
      const left = slices[0].charX;
      const right = slices[slices.length - 1].charX + slices[slices.length - 1].charWidth;
      const middle = (left + right) / 2;
      fragment2.glyphs.forEach((glyph, offsetInWord) => {
        const slice = slices[offsetInWord];
        const sprite = new pixi.Sprite(slice.texture);
        sprite.anchor.set(slice.anchorX, slice.anchorY);
        sprite.visible = !glyph.blank;
        holders[index].addChild(sprite);
        glyph.sprite = sprite;
        glyph.offset = slice.charX + slice.charWidth / 2 - middle;
      });
    }
  };
  const release = (echoLine) => {
    for (let index = echoLine.first; index < echoLine.last; index += 1) {
      holders[index].removeChildren().forEach((child) => child.destroy());
      fragments[index].glyphs.forEach((glyph) => {
        glyph.sprite = null;
      });
    }
    echoLine.layout?.destroy();
    echoLine.layout = null;
  };
  const prepare = (time) => {
    let budget = 1;
    for (const echoLine of echoLines) {
      if (time < echoLine.from - PREPARE || time > echoLine.to + LIFE) {
        if (echoLine.layout) release(echoLine);
      } else if (!echoLine.layout && (time >= echoLine.from || budget-- > 0)) {
        rasterize(echoLine);
      }
    }
  };
  const hasKeywords = fragments.some((fragment2) => fragment2.glyphs.some((glyph) => glyph.keyword));
  const keywordHex = /* @__PURE__ */ new Map();
  let keywordFor = -1;
  const keywordTint = (color, keyword) => {
    if (color !== keywordFor) {
      keywordHex.clear();
      keywordFor = color;
    }
    let hex = keywordHex.get(keyword);
    if (hex === void 0) {
      const light = [(color >> 16 & 255) / 255, (color >> 8 & 255) / 255, (color & 255) / 255];
      hex = hexOf(keywordEchoColor(light, keyword));
      keywordHex.set(keyword, hex);
    }
    return hex;
  };
  const update = ({ time, beams, color, intensity }) => {
    prepare(time);
    const beam = beams[0];
    const ox = beam?.ox ?? options.width / height / 2;
    const oy = beam?.oy ?? 0;
    const bx = beam?.dx ?? 0;
    const by = beam?.dy ?? 1;
    const halfAt = (distance) => (beam ? beam.halfWidth + distance * beam.tanSpread : 0.08) + 0.04;
    fragments.forEach((fragment2, index) => {
      const holder = holders[index];
      const age = time - fragment2.birth;
      const presence = smooth(age / 0.9) * (1 - smooth((age - (LIFE - 2.5)) / 2.5));
      const alpha = presence * intensity * options.opacity;
      holder.visible = age >= 0 && age <= LIFE && alpha > 3e-3;
      if (!holder.visible) return;
      const distance = BIRTH_DISTANCE + SPEED * fragment2.speed * age;
      const across = fragment2.across * halfAt(distance);
      const x = (ox + bx * distance - by * across) * height;
      const y = (oy + by * distance + bx * across) * height;
      holder.position.set(x, y);
      holder.rotation = fragment2.rotation + fragment2.spin * age;
      holder.scale.set(fragment2.scale * fragment2.stretch, fragment2.scale);
      holder.skew.set(fragment2.shear * age, 0);
      const split = 0.05 * age ** 1.3;
      const lit = compressLight(lightAt(beams, x / height, y / height));
      const glyphAlpha = alpha * (0.05 + 0.4 * lit);
      for (const glyph of fragment2.glyphs) {
        if (!glyph.sprite) continue;
        glyph.sprite.position.set(
          glyph.offset + glyph.dx * fontPx * split * glyph.speed,
          glyph.dy * fontPx * split * glyph.speed
        );
        glyph.sprite.rotation = glyph.spin * split * 4;
        glyph.sprite.alpha = glyphAlpha;
        glyph.sprite.tint = hasKeywords && glyph.keyword ? keywordTint(color, glyph.keyword) : color;
      }
    });
  };
  return {
    view,
    update,
    destroy: () => {
      view.destroy({ children: true });
      echoLines.forEach((echoLine) => echoLine.layout?.destroy());
    }
  };
};

// scripts/folia/node_modules/@chenglou/pretext/dist/generated/bidi-data.js
var latin1BidiTypes = [
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "S",
  "B",
  "S",
  "WS",
  "B",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "B",
  "B",
  "B",
  "S",
  "WS",
  "ON",
  "ON",
  "ET",
  "ET",
  "ET",
  "ON",
  "ON",
  "ON",
  "ON",
  "ON",
  "ES",
  "CS",
  "ES",
  "CS",
  "CS",
  "EN",
  "EN",
  "EN",
  "EN",
  "EN",
  "EN",
  "EN",
  "EN",
  "EN",
  "EN",
  "CS",
  "ON",
  "ON",
  "ON",
  "ON",
  "ON",
  "ON",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "ON",
  "ON",
  "ON",
  "ON",
  "ON",
  "ON",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "ON",
  "ON",
  "ON",
  "ON",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "B",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "BN",
  "CS",
  "ON",
  "ET",
  "ET",
  "ET",
  "ET",
  "ON",
  "ON",
  "ON",
  "ON",
  "L",
  "ON",
  "ON",
  "BN",
  "ON",
  "ON",
  "ET",
  "ET",
  "EN",
  "EN",
  "ON",
  "L",
  "ON",
  "ON",
  "ON",
  "EN",
  "L",
  "ON",
  "ON",
  "ON",
  "ON",
  "ON",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "ON",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "ON",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L",
  "L"
];
var nonLatin1BidiRanges = [
  [697, 698, "ON"],
  [706, 719, "ON"],
  [722, 735, "ON"],
  [741, 749, "ON"],
  [751, 767, "ON"],
  [768, 879, "NSM"],
  [884, 885, "ON"],
  [894, 894, "ON"],
  [900, 901, "ON"],
  [903, 903, "ON"],
  [1014, 1014, "ON"],
  [1155, 1161, "NSM"],
  [1418, 1418, "ON"],
  [1421, 1422, "ON"],
  [1423, 1423, "ET"],
  [1424, 1424, "R"],
  [1425, 1469, "NSM"],
  [1470, 1470, "R"],
  [1471, 1471, "NSM"],
  [1472, 1472, "R"],
  [1473, 1474, "NSM"],
  [1475, 1475, "R"],
  [1476, 1477, "NSM"],
  [1478, 1478, "R"],
  [1479, 1479, "NSM"],
  [1480, 1535, "R"],
  [1536, 1541, "AN"],
  [1542, 1543, "ON"],
  [1544, 1544, "AL"],
  [1545, 1546, "ET"],
  [1547, 1547, "AL"],
  [1548, 1548, "CS"],
  [1549, 1549, "AL"],
  [1550, 1551, "ON"],
  [1552, 1562, "NSM"],
  [1563, 1610, "AL"],
  [1611, 1631, "NSM"],
  [1632, 1641, "AN"],
  [1642, 1642, "ET"],
  [1643, 1644, "AN"],
  [1645, 1647, "AL"],
  [1648, 1648, "NSM"],
  [1649, 1749, "AL"],
  [1750, 1756, "NSM"],
  [1757, 1757, "AN"],
  [1758, 1758, "ON"],
  [1759, 1764, "NSM"],
  [1765, 1766, "AL"],
  [1767, 1768, "NSM"],
  [1769, 1769, "ON"],
  [1770, 1773, "NSM"],
  [1774, 1775, "AL"],
  [1776, 1785, "EN"],
  [1786, 1808, "AL"],
  [1809, 1809, "NSM"],
  [1810, 1839, "AL"],
  [1840, 1866, "NSM"],
  [1867, 1957, "AL"],
  [1958, 1968, "NSM"],
  [1969, 1983, "AL"],
  [1984, 2026, "R"],
  [2027, 2035, "NSM"],
  [2036, 2037, "R"],
  [2038, 2041, "ON"],
  [2042, 2044, "R"],
  [2045, 2045, "NSM"],
  [2046, 2069, "R"],
  [2070, 2073, "NSM"],
  [2074, 2074, "R"],
  [2075, 2083, "NSM"],
  [2084, 2084, "R"],
  [2085, 2087, "NSM"],
  [2088, 2088, "R"],
  [2089, 2093, "NSM"],
  [2094, 2136, "R"],
  [2137, 2139, "NSM"],
  [2140, 2143, "R"],
  [2144, 2191, "AL"],
  [2192, 2193, "AN"],
  [2194, 2198, "AL"],
  [2199, 2207, "NSM"],
  [2208, 2249, "AL"],
  [2250, 2273, "NSM"],
  [2274, 2274, "AN"],
  [2275, 2306, "NSM"],
  [2362, 2362, "NSM"],
  [2364, 2364, "NSM"],
  [2369, 2376, "NSM"],
  [2381, 2381, "NSM"],
  [2385, 2391, "NSM"],
  [2402, 2403, "NSM"],
  [2433, 2433, "NSM"],
  [2492, 2492, "NSM"],
  [2497, 2500, "NSM"],
  [2509, 2509, "NSM"],
  [2530, 2531, "NSM"],
  [2546, 2547, "ET"],
  [2555, 2555, "ET"],
  [2558, 2558, "NSM"],
  [2561, 2562, "NSM"],
  [2620, 2620, "NSM"],
  [2625, 2626, "NSM"],
  [2631, 2632, "NSM"],
  [2635, 2637, "NSM"],
  [2641, 2641, "NSM"],
  [2672, 2673, "NSM"],
  [2677, 2677, "NSM"],
  [2689, 2690, "NSM"],
  [2748, 2748, "NSM"],
  [2753, 2757, "NSM"],
  [2759, 2760, "NSM"],
  [2765, 2765, "NSM"],
  [2786, 2787, "NSM"],
  [2801, 2801, "ET"],
  [2810, 2815, "NSM"],
  [2817, 2817, "NSM"],
  [2876, 2876, "NSM"],
  [2879, 2879, "NSM"],
  [2881, 2884, "NSM"],
  [2893, 2893, "NSM"],
  [2901, 2902, "NSM"],
  [2914, 2915, "NSM"],
  [2946, 2946, "NSM"],
  [3008, 3008, "NSM"],
  [3021, 3021, "NSM"],
  [3059, 3064, "ON"],
  [3065, 3065, "ET"],
  [3066, 3066, "ON"],
  [3072, 3072, "NSM"],
  [3076, 3076, "NSM"],
  [3132, 3132, "NSM"],
  [3134, 3136, "NSM"],
  [3142, 3144, "NSM"],
  [3146, 3149, "NSM"],
  [3157, 3158, "NSM"],
  [3170, 3171, "NSM"],
  [3192, 3198, "ON"],
  [3201, 3201, "NSM"],
  [3260, 3260, "NSM"],
  [3276, 3277, "NSM"],
  [3298, 3299, "NSM"],
  [3328, 3329, "NSM"],
  [3387, 3388, "NSM"],
  [3393, 3396, "NSM"],
  [3405, 3405, "NSM"],
  [3426, 3427, "NSM"],
  [3457, 3457, "NSM"],
  [3530, 3530, "NSM"],
  [3538, 3540, "NSM"],
  [3542, 3542, "NSM"],
  [3633, 3633, "NSM"],
  [3636, 3642, "NSM"],
  [3647, 3647, "ET"],
  [3655, 3662, "NSM"],
  [3761, 3761, "NSM"],
  [3764, 3772, "NSM"],
  [3784, 3790, "NSM"],
  [3864, 3865, "NSM"],
  [3893, 3893, "NSM"],
  [3895, 3895, "NSM"],
  [3897, 3897, "NSM"],
  [3898, 3901, "ON"],
  [3953, 3966, "NSM"],
  [3968, 3972, "NSM"],
  [3974, 3975, "NSM"],
  [3981, 3991, "NSM"],
  [3993, 4028, "NSM"],
  [4038, 4038, "NSM"],
  [4141, 4144, "NSM"],
  [4146, 4151, "NSM"],
  [4153, 4154, "NSM"],
  [4157, 4158, "NSM"],
  [4184, 4185, "NSM"],
  [4190, 4192, "NSM"],
  [4209, 4212, "NSM"],
  [4226, 4226, "NSM"],
  [4229, 4230, "NSM"],
  [4237, 4237, "NSM"],
  [4253, 4253, "NSM"],
  [4957, 4959, "NSM"],
  [5008, 5017, "ON"],
  [5120, 5120, "ON"],
  [5760, 5760, "WS"],
  [5787, 5788, "ON"],
  [5906, 5908, "NSM"],
  [5938, 5939, "NSM"],
  [5970, 5971, "NSM"],
  [6002, 6003, "NSM"],
  [6068, 6069, "NSM"],
  [6071, 6077, "NSM"],
  [6086, 6086, "NSM"],
  [6089, 6099, "NSM"],
  [6107, 6107, "ET"],
  [6109, 6109, "NSM"],
  [6128, 6137, "ON"],
  [6144, 6154, "ON"],
  [6155, 6157, "NSM"],
  [6158, 6158, "BN"],
  [6159, 6159, "NSM"],
  [6277, 6278, "NSM"],
  [6313, 6313, "NSM"],
  [6432, 6434, "NSM"],
  [6439, 6440, "NSM"],
  [6450, 6450, "NSM"],
  [6457, 6459, "NSM"],
  [6464, 6464, "ON"],
  [6468, 6469, "ON"],
  [6622, 6655, "ON"],
  [6679, 6680, "NSM"],
  [6683, 6683, "NSM"],
  [6742, 6742, "NSM"],
  [6744, 6750, "NSM"],
  [6752, 6752, "NSM"],
  [6754, 6754, "NSM"],
  [6757, 6764, "NSM"],
  [6771, 6780, "NSM"],
  [6783, 6783, "NSM"],
  [6832, 6877, "NSM"],
  [6880, 6891, "NSM"],
  [6912, 6915, "NSM"],
  [6964, 6964, "NSM"],
  [6966, 6970, "NSM"],
  [6972, 6972, "NSM"],
  [6978, 6978, "NSM"],
  [7019, 7027, "NSM"],
  [7040, 7041, "NSM"],
  [7074, 7077, "NSM"],
  [7080, 7081, "NSM"],
  [7083, 7085, "NSM"],
  [7142, 7142, "NSM"],
  [7144, 7145, "NSM"],
  [7149, 7149, "NSM"],
  [7151, 7153, "NSM"],
  [7212, 7219, "NSM"],
  [7222, 7223, "NSM"],
  [7376, 7378, "NSM"],
  [7380, 7392, "NSM"],
  [7394, 7400, "NSM"],
  [7405, 7405, "NSM"],
  [7412, 7412, "NSM"],
  [7416, 7417, "NSM"],
  [7616, 7679, "NSM"],
  [8125, 8125, "ON"],
  [8127, 8129, "ON"],
  [8141, 8143, "ON"],
  [8157, 8159, "ON"],
  [8173, 8175, "ON"],
  [8189, 8190, "ON"],
  [8192, 8202, "WS"],
  [8203, 8205, "BN"],
  [8207, 8207, "R"],
  [8208, 8231, "ON"],
  [8232, 8232, "WS"],
  [8233, 8233, "B"],
  [8234, 8238, "BN"],
  [8239, 8239, "CS"],
  [8240, 8244, "ET"],
  [8245, 8259, "ON"],
  [8260, 8260, "CS"],
  [8261, 8286, "ON"],
  [8287, 8287, "WS"],
  [8288, 8303, "BN"],
  [8304, 8304, "EN"],
  [8308, 8313, "EN"],
  [8314, 8315, "ES"],
  [8316, 8318, "ON"],
  [8320, 8329, "EN"],
  [8330, 8331, "ES"],
  [8332, 8334, "ON"],
  [8352, 8399, "ET"],
  [8400, 8432, "NSM"],
  [8448, 8449, "ON"],
  [8451, 8454, "ON"],
  [8456, 8457, "ON"],
  [8468, 8468, "ON"],
  [8470, 8472, "ON"],
  [8478, 8483, "ON"],
  [8485, 8485, "ON"],
  [8487, 8487, "ON"],
  [8489, 8489, "ON"],
  [8494, 8494, "ET"],
  [8506, 8507, "ON"],
  [8512, 8516, "ON"],
  [8522, 8525, "ON"],
  [8528, 8543, "ON"],
  [8585, 8587, "ON"],
  [8592, 8721, "ON"],
  [8722, 8722, "ES"],
  [8723, 8723, "ET"],
  [8724, 9013, "ON"],
  [9083, 9108, "ON"],
  [9110, 9257, "ON"],
  [9280, 9290, "ON"],
  [9312, 9351, "ON"],
  [9352, 9371, "EN"],
  [9450, 9899, "ON"],
  [9901, 10239, "ON"],
  [10496, 11123, "ON"],
  [11126, 11263, "ON"],
  [11493, 11498, "ON"],
  [11503, 11505, "NSM"],
  [11513, 11519, "ON"],
  [11647, 11647, "NSM"],
  [11744, 11775, "NSM"],
  [11776, 11869, "ON"],
  [11904, 11929, "ON"],
  [11931, 12019, "ON"],
  [12032, 12245, "ON"],
  [12272, 12287, "ON"],
  [12288, 12288, "WS"],
  [12289, 12292, "ON"],
  [12296, 12320, "ON"],
  [12330, 12333, "NSM"],
  [12336, 12336, "ON"],
  [12342, 12343, "ON"],
  [12349, 12351, "ON"],
  [12441, 12442, "NSM"],
  [12443, 12444, "ON"],
  [12448, 12448, "ON"],
  [12539, 12539, "ON"],
  [12736, 12773, "ON"],
  [12783, 12783, "ON"],
  [12829, 12830, "ON"],
  [12880, 12895, "ON"],
  [12924, 12926, "ON"],
  [12977, 12991, "ON"],
  [13004, 13007, "ON"],
  [13175, 13178, "ON"],
  [13278, 13279, "ON"],
  [13311, 13311, "ON"],
  [19904, 19967, "ON"],
  [42128, 42182, "ON"],
  [42509, 42511, "ON"],
  [42607, 42610, "NSM"],
  [42611, 42611, "ON"],
  [42612, 42621, "NSM"],
  [42622, 42623, "ON"],
  [42654, 42655, "NSM"],
  [42736, 42737, "NSM"],
  [42752, 42785, "ON"],
  [42888, 42888, "ON"],
  [43010, 43010, "NSM"],
  [43014, 43014, "NSM"],
  [43019, 43019, "NSM"],
  [43045, 43046, "NSM"],
  [43048, 43051, "ON"],
  [43052, 43052, "NSM"],
  [43064, 43065, "ET"],
  [43124, 43127, "ON"],
  [43204, 43205, "NSM"],
  [43232, 43249, "NSM"],
  [43263, 43263, "NSM"],
  [43302, 43309, "NSM"],
  [43335, 43345, "NSM"],
  [43392, 43394, "NSM"],
  [43443, 43443, "NSM"],
  [43446, 43449, "NSM"],
  [43452, 43453, "NSM"],
  [43493, 43493, "NSM"],
  [43561, 43566, "NSM"],
  [43569, 43570, "NSM"],
  [43573, 43574, "NSM"],
  [43587, 43587, "NSM"],
  [43596, 43596, "NSM"],
  [43644, 43644, "NSM"],
  [43696, 43696, "NSM"],
  [43698, 43700, "NSM"],
  [43703, 43704, "NSM"],
  [43710, 43711, "NSM"],
  [43713, 43713, "NSM"],
  [43756, 43757, "NSM"],
  [43766, 43766, "NSM"],
  [43882, 43883, "ON"],
  [44005, 44005, "NSM"],
  [44008, 44008, "NSM"],
  [44013, 44013, "NSM"],
  [64285, 64285, "R"],
  [64286, 64286, "NSM"],
  [64287, 64296, "R"],
  [64297, 64297, "ES"],
  [64298, 64335, "R"],
  [64336, 64450, "AL"],
  [64451, 64466, "ON"],
  [64467, 64829, "AL"],
  [64830, 64847, "ON"],
  [64848, 64911, "AL"],
  [64912, 64913, "ON"],
  [64914, 64967, "AL"],
  [64968, 64975, "ON"],
  [64976, 65007, "BN"],
  [65008, 65020, "AL"],
  [65021, 65023, "ON"],
  [65024, 65039, "NSM"],
  [65040, 65049, "ON"],
  [65056, 65071, "NSM"],
  [65072, 65103, "ON"],
  [65104, 65104, "CS"],
  [65105, 65105, "ON"],
  [65106, 65106, "CS"],
  [65108, 65108, "ON"],
  [65109, 65109, "CS"],
  [65110, 65118, "ON"],
  [65119, 65119, "ET"],
  [65120, 65121, "ON"],
  [65122, 65123, "ES"],
  [65124, 65126, "ON"],
  [65128, 65128, "ON"],
  [65129, 65130, "ET"],
  [65131, 65131, "ON"],
  [65136, 65278, "AL"],
  [65279, 65279, "BN"],
  [65281, 65282, "ON"],
  [65283, 65285, "ET"],
  [65286, 65290, "ON"],
  [65291, 65291, "ES"],
  [65292, 65292, "CS"],
  [65293, 65293, "ES"],
  [65294, 65295, "CS"],
  [65296, 65305, "EN"],
  [65306, 65306, "CS"],
  [65307, 65312, "ON"],
  [65339, 65344, "ON"],
  [65371, 65381, "ON"],
  [65504, 65505, "ET"],
  [65506, 65508, "ON"],
  [65509, 65510, "ET"],
  [65512, 65518, "ON"],
  [65520, 65528, "BN"],
  [65529, 65533, "ON"],
  [65534, 65535, "BN"],
  [65793, 65793, "ON"],
  [65856, 65932, "ON"],
  [65936, 65948, "ON"],
  [65952, 65952, "ON"],
  [66045, 66045, "NSM"],
  [66272, 66272, "NSM"],
  [66273, 66299, "EN"],
  [66422, 66426, "NSM"],
  [67584, 67870, "R"],
  [67871, 67871, "ON"],
  [67872, 68096, "R"],
  [68097, 68099, "NSM"],
  [68100, 68100, "R"],
  [68101, 68102, "NSM"],
  [68103, 68107, "R"],
  [68108, 68111, "NSM"],
  [68112, 68151, "R"],
  [68152, 68154, "NSM"],
  [68155, 68158, "R"],
  [68159, 68159, "NSM"],
  [68160, 68324, "R"],
  [68325, 68326, "NSM"],
  [68327, 68408, "R"],
  [68409, 68415, "ON"],
  [68416, 68863, "R"],
  [68864, 68899, "AL"],
  [68900, 68903, "NSM"],
  [68904, 68911, "AL"],
  [68912, 68921, "AN"],
  [68922, 68927, "AL"],
  [68928, 68937, "AN"],
  [68938, 68968, "R"],
  [68969, 68973, "NSM"],
  [68974, 68974, "ON"],
  [68975, 69215, "R"],
  [69216, 69246, "AN"],
  [69247, 69290, "R"],
  [69291, 69292, "NSM"],
  [69293, 69311, "R"],
  [69312, 69327, "AL"],
  [69328, 69336, "ON"],
  [69337, 69369, "AL"],
  [69370, 69375, "NSM"],
  [69376, 69423, "R"],
  [69424, 69445, "AL"],
  [69446, 69456, "NSM"],
  [69457, 69487, "AL"],
  [69488, 69505, "R"],
  [69506, 69509, "NSM"],
  [69510, 69631, "R"],
  [69633, 69633, "NSM"],
  [69688, 69702, "NSM"],
  [69714, 69733, "ON"],
  [69744, 69744, "NSM"],
  [69747, 69748, "NSM"],
  [69759, 69761, "NSM"],
  [69811, 69814, "NSM"],
  [69817, 69818, "NSM"],
  [69826, 69826, "NSM"],
  [69888, 69890, "NSM"],
  [69927, 69931, "NSM"],
  [69933, 69940, "NSM"],
  [70003, 70003, "NSM"],
  [70016, 70017, "NSM"],
  [70070, 70078, "NSM"],
  [70089, 70092, "NSM"],
  [70095, 70095, "NSM"],
  [70191, 70193, "NSM"],
  [70196, 70196, "NSM"],
  [70198, 70199, "NSM"],
  [70206, 70206, "NSM"],
  [70209, 70209, "NSM"],
  [70367, 70367, "NSM"],
  [70371, 70378, "NSM"],
  [70400, 70401, "NSM"],
  [70459, 70460, "NSM"],
  [70464, 70464, "NSM"],
  [70502, 70508, "NSM"],
  [70512, 70516, "NSM"],
  [70587, 70592, "NSM"],
  [70606, 70606, "NSM"],
  [70608, 70608, "NSM"],
  [70610, 70610, "NSM"],
  [70625, 70626, "NSM"],
  [70712, 70719, "NSM"],
  [70722, 70724, "NSM"],
  [70726, 70726, "NSM"],
  [70750, 70750, "NSM"],
  [70835, 70840, "NSM"],
  [70842, 70842, "NSM"],
  [70847, 70848, "NSM"],
  [70850, 70851, "NSM"],
  [71090, 71093, "NSM"],
  [71100, 71101, "NSM"],
  [71103, 71104, "NSM"],
  [71132, 71133, "NSM"],
  [71219, 71226, "NSM"],
  [71229, 71229, "NSM"],
  [71231, 71232, "NSM"],
  [71264, 71276, "ON"],
  [71339, 71339, "NSM"],
  [71341, 71341, "NSM"],
  [71344, 71349, "NSM"],
  [71351, 71351, "NSM"],
  [71453, 71453, "NSM"],
  [71455, 71455, "NSM"],
  [71458, 71461, "NSM"],
  [71463, 71467, "NSM"],
  [71727, 71735, "NSM"],
  [71737, 71738, "NSM"],
  [71995, 71996, "NSM"],
  [71998, 71998, "NSM"],
  [72003, 72003, "NSM"],
  [72148, 72151, "NSM"],
  [72154, 72155, "NSM"],
  [72160, 72160, "NSM"],
  [72193, 72198, "NSM"],
  [72201, 72202, "NSM"],
  [72243, 72248, "NSM"],
  [72251, 72254, "NSM"],
  [72263, 72263, "NSM"],
  [72273, 72278, "NSM"],
  [72281, 72283, "NSM"],
  [72330, 72342, "NSM"],
  [72344, 72345, "NSM"],
  [72544, 72544, "NSM"],
  [72546, 72548, "NSM"],
  [72550, 72550, "NSM"],
  [72752, 72758, "NSM"],
  [72760, 72765, "NSM"],
  [72850, 72871, "NSM"],
  [72874, 72880, "NSM"],
  [72882, 72883, "NSM"],
  [72885, 72886, "NSM"],
  [73009, 73014, "NSM"],
  [73018, 73018, "NSM"],
  [73020, 73021, "NSM"],
  [73023, 73029, "NSM"],
  [73031, 73031, "NSM"],
  [73104, 73105, "NSM"],
  [73109, 73109, "NSM"],
  [73111, 73111, "NSM"],
  [73459, 73460, "NSM"],
  [73472, 73473, "NSM"],
  [73526, 73530, "NSM"],
  [73536, 73536, "NSM"],
  [73538, 73538, "NSM"],
  [73562, 73562, "NSM"],
  [73685, 73692, "ON"],
  [73693, 73696, "ET"],
  [73697, 73713, "ON"],
  [78912, 78912, "NSM"],
  [78919, 78933, "NSM"],
  [90398, 90409, "NSM"],
  [90413, 90415, "NSM"],
  [92912, 92916, "NSM"],
  [92976, 92982, "NSM"],
  [94031, 94031, "NSM"],
  [94095, 94098, "NSM"],
  [94178, 94178, "ON"],
  [94180, 94180, "NSM"],
  [113821, 113822, "NSM"],
  [113824, 113827, "BN"],
  [117760, 117973, "ON"],
  [118e3, 118009, "EN"],
  [118010, 118012, "ON"],
  [118016, 118451, "ON"],
  [118458, 118480, "ON"],
  [118496, 118512, "ON"],
  [118528, 118573, "NSM"],
  [118576, 118598, "NSM"],
  [119143, 119145, "NSM"],
  [119155, 119162, "BN"],
  [119163, 119170, "NSM"],
  [119173, 119179, "NSM"],
  [119210, 119213, "NSM"],
  [119273, 119274, "ON"],
  [119296, 119361, "ON"],
  [119362, 119364, "NSM"],
  [119365, 119365, "ON"],
  [119552, 119638, "ON"],
  [120513, 120513, "ON"],
  [120539, 120539, "ON"],
  [120571, 120571, "ON"],
  [120597, 120597, "ON"],
  [120629, 120629, "ON"],
  [120655, 120655, "ON"],
  [120687, 120687, "ON"],
  [120713, 120713, "ON"],
  [120745, 120745, "ON"],
  [120771, 120771, "ON"],
  [120782, 120831, "EN"],
  [121344, 121398, "NSM"],
  [121403, 121452, "NSM"],
  [121461, 121461, "NSM"],
  [121476, 121476, "NSM"],
  [121499, 121503, "NSM"],
  [121505, 121519, "NSM"],
  [122880, 122886, "NSM"],
  [122888, 122904, "NSM"],
  [122907, 122913, "NSM"],
  [122915, 122916, "NSM"],
  [122918, 122922, "NSM"],
  [123023, 123023, "NSM"],
  [123184, 123190, "NSM"],
  [123566, 123566, "NSM"],
  [123628, 123631, "NSM"],
  [123647, 123647, "ET"],
  [124140, 124143, "NSM"],
  [124398, 124399, "NSM"],
  [124643, 124643, "NSM"],
  [124646, 124646, "NSM"],
  [124654, 124655, "NSM"],
  [124661, 124661, "NSM"],
  [124928, 125135, "R"],
  [125136, 125142, "NSM"],
  [125143, 125251, "R"],
  [125252, 125258, "NSM"],
  [125259, 126063, "R"],
  [126064, 126143, "AL"],
  [126144, 126207, "R"],
  [126208, 126287, "AL"],
  [126288, 126463, "R"],
  [126464, 126703, "AL"],
  [126704, 126705, "ON"],
  [126706, 126719, "AL"],
  [126720, 126975, "R"],
  [126976, 127019, "ON"],
  [127024, 127123, "ON"],
  [127136, 127150, "ON"],
  [127153, 127167, "ON"],
  [127169, 127183, "ON"],
  [127185, 127221, "ON"],
  [127232, 127242, "EN"],
  [127243, 127247, "ON"],
  [127279, 127279, "ON"],
  [127338, 127343, "ON"],
  [127405, 127405, "ON"],
  [127584, 127589, "ON"],
  [127744, 128728, "ON"],
  [128732, 128748, "ON"],
  [128752, 128764, "ON"],
  [128768, 128985, "ON"],
  [128992, 129003, "ON"],
  [129008, 129008, "ON"],
  [129024, 129035, "ON"],
  [129040, 129095, "ON"],
  [129104, 129113, "ON"],
  [129120, 129159, "ON"],
  [129168, 129197, "ON"],
  [129200, 129211, "ON"],
  [129216, 129217, "ON"],
  [129232, 129240, "ON"],
  [129280, 129623, "ON"],
  [129632, 129645, "ON"],
  [129648, 129660, "ON"],
  [129664, 129674, "ON"],
  [129678, 129734, "ON"],
  [129736, 129736, "ON"],
  [129741, 129756, "ON"],
  [129759, 129770, "ON"],
  [129775, 129784, "ON"],
  [129792, 129938, "ON"],
  [129940, 130031, "ON"],
  [130032, 130041, "EN"],
  [130042, 130042, "ON"],
  [131070, 131071, "BN"],
  [196606, 196607, "BN"],
  [262142, 262143, "BN"],
  [327678, 327679, "BN"],
  [393214, 393215, "BN"],
  [458750, 458751, "BN"],
  [524286, 524287, "BN"],
  [589822, 589823, "BN"],
  [655358, 655359, "BN"],
  [720894, 720895, "BN"],
  [786430, 786431, "BN"],
  [851966, 851967, "BN"],
  [917502, 917759, "BN"],
  [917760, 917999, "NSM"],
  [918e3, 921599, "BN"],
  [983038, 983039, "BN"],
  [1048574, 1048575, "BN"],
  [1114110, 1114111, "BN"]
];

// scripts/folia/node_modules/@chenglou/pretext/dist/bidi.js
function classifyCodePoint(codePoint) {
  if (codePoint <= 255)
    return latin1BidiTypes[codePoint];
  let lo = 0;
  let hi = nonLatin1BidiRanges.length - 1;
  while (lo <= hi) {
    const mid = lo + hi >> 1;
    const range = nonLatin1BidiRanges[mid];
    if (codePoint < range[0]) {
      hi = mid - 1;
      continue;
    }
    if (codePoint > range[1]) {
      lo = mid + 1;
      continue;
    }
    return range[2];
  }
  return "L";
}
function computeBidiLevels(str) {
  const len = str.length;
  if (len === 0)
    return null;
  const types = new Array(len);
  let paragraphHasBidi = false;
  let paragraphStart = 0;
  let levels = null;
  for (let i = 0; i < len; ) {
    const first = str.charCodeAt(i);
    let codePoint = first;
    let codeUnitLength = 1;
    if (first >= 55296 && first <= 56319 && i + 1 < len) {
      const second = str.charCodeAt(i + 1);
      if (second >= 56320 && second <= 57343) {
        codePoint = (first - 55296 << 10) + (second - 56320) + 65536;
        codeUnitLength = 2;
      }
    }
    const t = classifyCodePoint(codePoint);
    if (t === "R" || t === "AL" || t === "AN")
      paragraphHasBidi = true;
    for (let j = 0; j < codeUnitLength; j++) {
      types[i + j] = t;
    }
    if (t === "B") {
      if (paragraphHasBidi) {
        levels ??= new Int8Array(len);
        levels[i] = resolveParagraphLevels(types, levels, paragraphStart, i);
      }
      paragraphStart = i + codeUnitLength;
      paragraphHasBidi = false;
    }
    i += codeUnitLength;
  }
  if (paragraphHasBidi) {
    levels ??= new Int8Array(len);
    resolveParagraphLevels(types, levels, paragraphStart, len);
  }
  return levels;
}
function resolveParagraphLevels(types, levels, start, end) {
  let startLevel = 0;
  for (let i = start; i < end; i++) {
    const t = types[i];
    if (t === "L") {
      startLevel = 0;
      break;
    }
    if (t === "R" || t === "AL") {
      startLevel = 1;
      break;
    }
  }
  const e = startLevel & 1 ? "R" : "L";
  const sor = e;
  let lastType = sor;
  for (let i = start; i < end; i++) {
    if (types[i] === "NSM")
      types[i] = lastType;
    else
      lastType = types[i];
  }
  lastType = sor;
  for (let i = start; i < end; i++) {
    const t = types[i];
    if (t === "EN")
      types[i] = lastType === "AL" ? "AN" : "EN";
    else if (t === "R" || t === "L" || t === "AL")
      lastType = t;
  }
  for (let i = start; i < end; i++) {
    if (types[i] === "AL")
      types[i] = "R";
  }
  for (let i = start + 1; i < end - 1; i++) {
    if (types[i] === "ES" && types[i - 1] === "EN" && types[i + 1] === "EN") {
      types[i] = "EN";
    }
    if (types[i] === "CS" && (types[i - 1] === "EN" || types[i - 1] === "AN") && types[i + 1] === types[i - 1]) {
      types[i] = types[i - 1];
    }
  }
  for (let i = start; i < end; i++) {
    if (types[i] !== "EN")
      continue;
    let j;
    for (j = i - 1; j >= start && types[j] === "ET"; j--)
      types[j] = "EN";
    for (j = i + 1; j < end && types[j] === "ET"; j++)
      types[j] = "EN";
  }
  for (let i = start; i < end; i++) {
    const t = types[i];
    if (t === "WS" || t === "ES" || t === "ET" || t === "CS")
      types[i] = "ON";
  }
  lastType = sor;
  for (let i = start; i < end; i++) {
    const t = types[i];
    if (t === "EN")
      types[i] = lastType === "L" ? "L" : "EN";
    else if (t === "R" || t === "L")
      lastType = t;
  }
  for (let i = start; i < end; i++) {
    if (types[i] !== "ON")
      continue;
    let runEnd = i + 1;
    while (runEnd < end && types[runEnd] === "ON")
      runEnd++;
    const before = i > start ? types[i - 1] : sor;
    const after = runEnd < end ? types[runEnd] : sor;
    const bDir = before !== "L" ? "R" : "L";
    const aDir = after !== "L" ? "R" : "L";
    if (bDir === aDir) {
      for (let j = i; j < runEnd; j++)
        types[j] = bDir;
    }
    i = runEnd - 1;
  }
  for (let i = start; i < end; i++) {
    if (types[i] === "ON")
      types[i] = e;
  }
  for (let i = start; i < end; i++) {
    const t = types[i];
    let level = startLevel;
    if ((startLevel & 1) === 0) {
      if (t === "R")
        level++;
      else if (t === "AN" || t === "EN")
        level += 2;
    } else if (t === "L" || t === "AN" || t === "EN") {
      level++;
    }
    levels[i] = level;
  }
  return startLevel;
}
function computeSegmentLevels(normalized, segStarts) {
  const bidiLevels = computeBidiLevels(normalized);
  if (bidiLevels === null)
    return null;
  const segLevels = new Int8Array(segStarts.length);
  for (let i = 0; i < segStarts.length; i++) {
    segLevels[i] = bidiLevels[segStarts[i]];
  }
  return segLevels;
}

// scripts/folia/node_modules/@chenglou/pretext/dist/analysis.js
var collapsibleWhitespaceRunRe = /[ \t\n\r\f]+/g;
var needsWhitespaceNormalizationRe = /[\t\n\r\f]| {2,}|^ | $/;
function normalizeWhitespaceNormal(text) {
  if (!needsWhitespaceNormalizationRe.test(text))
    return text;
  let normalized = text.replace(collapsibleWhitespaceRunRe, " ");
  if (normalized.charCodeAt(0) === 32) {
    normalized = normalized.slice(1);
  }
  if (normalized.length > 0 && normalized.charCodeAt(normalized.length - 1) === 32) {
    normalized = normalized.slice(0, -1);
  }
  return normalized;
}
function normalizeWhitespacePreWrap(text) {
  if (!/[\r\f]/.test(text))
    return text;
  return text.replace(/\r\n/g, "\n").replace(/[\r\f]/g, "\n");
}
var sharedGraphemeSegmenter = null;
function getSharedGraphemeSegmenter() {
  if (sharedGraphemeSegmenter === null) {
    sharedGraphemeSegmenter = new Intl.Segmenter(void 0, { granularity: "grapheme" });
  }
  return sharedGraphemeSegmenter;
}
var sharedWordSegmenter = null;
var segmenterLocale;
function getSharedWordSegmenter() {
  if (sharedWordSegmenter === null) {
    sharedWordSegmenter = new Intl.Segmenter(segmenterLocale, { granularity: "word" });
  }
  return sharedWordSegmenter;
}
var arabicScriptRe = new RegExp("\\p{Script=Arabic}", "u");
var combiningMarkRe = new RegExp("\\p{M}", "u");
var decimalDigitRe = new RegExp("\\p{Nd}", "u");
function containsArabicScript(text) {
  return arabicScriptRe.test(text);
}
var cjkRe = /[\u3000-\u30FF\u3130-\u318F\u3400-\u4DBF\u4E00-\u9FFF\uAC00-\uD7AF\uF900-\uFAFF\uFF00-\uFFEF\u{20000}-\u{2A6DF}\u{2A700}-\u{2EE5D}\u{2F800}-\u{2FA1F}\u{30000}-\u{33479}]/u;
function isCJK2(s) {
  return cjkRe.test(s);
}
function endsWithLineStartProhibitedText(text) {
  const last = getLastCodePoint(text);
  return last !== null && (kinsokuStart.has(last) || leftStickyPunctuation.has(last));
}
var keepAllGlueChars = /* @__PURE__ */ new Set([
  "\xA0",
  "\u202F",
  "\u2060",
  "\uFEFF"
]);
var keepAllDashBreakChars = /* @__PURE__ */ new Set([
  "-",
  "\u2010",
  "\u2013",
  "\u2014"
]);
function endsWithKeepAllGlueText(text) {
  const last = getLastCodePoint(text);
  return last !== null && keepAllGlueChars.has(last);
}
function endsWithKeepAllDashBreakText(text) {
  const last = getLastCodePoint(text);
  return last !== null && keepAllDashBreakChars.has(last);
}
function canContinueKeepAllTextRun(previousText, breakAfterPunctuation) {
  if (endsWithKeepAllGlueText(previousText))
    return false;
  if (!breakAfterPunctuation)
    return true;
  if (endsWithLineStartProhibitedText(previousText))
    return false;
  if (endsWithKeepAllDashBreakText(previousText))
    return false;
  return true;
}
var kinsokuStart = /* @__PURE__ */ new Set([
  "\uFF0C",
  "\uFF0E",
  "\uFF01",
  "\uFF1A",
  "\uFF1B",
  "\uFF1F",
  "\u3001",
  "\u3002",
  "\u30FB",
  "\uFF09",
  "\u3015",
  "\u3009",
  "\u300B",
  "\u300D",
  "\u300F",
  "\u3011",
  "\u3017",
  "\u3019",
  "\u301B",
  "\u30FC",
  "\u3005",
  "\u303B",
  "\u309D",
  "\u309E",
  "\u30FD",
  "\u30FE"
]);
var kinsokuEnd = /* @__PURE__ */ new Set([
  '"',
  "(",
  "[",
  "{",
  "\xA1",
  "\xBF",
  "\u201C",
  "\u2018",
  "\u201A",
  "\u201E",
  "\xAB",
  "\u2039",
  "\u2E18",
  "\uFF08",
  "\u3014",
  "\u3008",
  "\u300A",
  "\u300C",
  "\u300E",
  "\u3010",
  "\u3016",
  "\u3018",
  "\u301A"
]);
var forwardStickyGlue = /* @__PURE__ */ new Set([
  "'",
  "\u2019"
]);
var leftStickyPunctuation = /* @__PURE__ */ new Set([
  ".",
  ",",
  "!",
  "?",
  ":",
  ";",
  "\u060C",
  "\u061B",
  "\u061F",
  "\u0964",
  "\u0965",
  "\u104A",
  "\u104B",
  "\u104C",
  "\u104D",
  "\u104F",
  ")",
  "]",
  "}",
  "%",
  '"',
  "\u201D",
  "\u2019",
  "\xBB",
  "\u203A",
  "\u2026"
]);
var arabicNoSpaceTrailingPunctuation = /* @__PURE__ */ new Set([
  ":",
  ".",
  "\u060C",
  "\u061B"
]);
var myanmarMedialGlue = /* @__PURE__ */ new Set([
  "\u104F"
]);
var closingQuoteChars = /* @__PURE__ */ new Set([
  "\u201D",
  "\u2019",
  "\xBB",
  "\u203A",
  "\u300D",
  "\u300F",
  "\u3011",
  "\u300B",
  "\u3009",
  "\u3015",
  "\uFF09"
]);
function isLeftStickyPunctuationSegment(segment2) {
  if (isPunctuationGlueCluster(segment2))
    return true;
  let sawPunctuation = false;
  for (const ch of segment2) {
    if (leftStickyPunctuation.has(ch) || isLineBreakNumericAffix(ch)) {
      sawPunctuation = true;
      continue;
    }
    if (sawPunctuation && combiningMarkRe.test(ch))
      continue;
    return false;
  }
  return sawPunctuation;
}
function isCJKLineStartProhibitedSegment(segment2) {
  for (const ch of segment2) {
    if (!kinsokuStart.has(ch) && !leftStickyPunctuation.has(ch))
      return false;
  }
  return segment2.length > 0;
}
function isForwardStickyClusterSegment(segment2) {
  if (isPunctuationGlueCluster(segment2))
    return true;
  for (const ch of segment2) {
    if (!kinsokuEnd.has(ch) && !forwardStickyGlue.has(ch) && !combiningMarkRe.test(ch) && !isLineBreakNumericAffix(ch)) {
      return false;
    }
  }
  return segment2.length > 0;
}
function isPunctuationGlueCluster(segment2) {
  let sawPunctuation = false;
  for (const ch of segment2) {
    if (ch === "\\" || combiningMarkRe.test(ch))
      continue;
    if (kinsokuEnd.has(ch) || leftStickyPunctuation.has(ch) || forwardStickyGlue.has(ch)) {
      sawPunctuation = true;
      continue;
    }
    return false;
  }
  return sawPunctuation;
}
function previousCodePointStart(text, end) {
  const last = end - 1;
  if (last <= 0)
    return Math.max(last, 0);
  const lastCodeUnit = text.charCodeAt(last);
  if (lastCodeUnit < 56320 || lastCodeUnit > 57343)
    return last;
  const maybeHigh = last - 1;
  if (maybeHigh < 0)
    return last;
  const highCodeUnit = text.charCodeAt(maybeHigh);
  return highCodeUnit >= 55296 && highCodeUnit <= 56319 ? maybeHigh : last;
}
function getLastCodePoint(text) {
  if (text.length === 0)
    return null;
  const start = previousCodePointStart(text, text.length);
  return text.slice(start);
}
function getFirstSignificantCodePoint(text) {
  for (const ch of text) {
    if (!combiningMarkRe.test(ch))
      return ch;
  }
  return null;
}
function getLastSignificantCodePoint(text, end = text.length) {
  for (; end > 0; ) {
    const start = previousCodePointStart(text, end);
    const ch = text.slice(start, end);
    if (!combiningMarkRe.test(ch))
      return ch;
    end = start;
  }
  return null;
}
var lineBreakNumericAffixRanges = [
  36,
  37,
  43,
  43,
  92,
  92,
  162,
  165,
  176,
  177,
  1423,
  1423,
  1545,
  1547,
  1642,
  1642,
  2046,
  2047,
  2546,
  2547,
  2553,
  2555,
  2801,
  2801,
  3065,
  3065,
  3449,
  3449,
  3647,
  3647,
  6107,
  6107,
  8240,
  8247,
  8279,
  8279,
  8352,
  8399,
  8451,
  8451,
  8457,
  8457,
  8470,
  8470,
  8722,
  8723,
  43064,
  43064,
  65020,
  65020,
  65129,
  65130,
  65284,
  65285,
  65504,
  65505,
  65509,
  65510,
  73693,
  73696,
  123647,
  123647,
  126124,
  126124,
  126128,
  126128
];
function isCodePointInRanges(codePoint, ranges) {
  for (let i = 0; i < ranges.length; i += 2) {
    if (codePoint >= ranges[i] && codePoint <= ranges[i + 1])
      return true;
  }
  return false;
}
function isLineBreakNumericAffix(ch) {
  const codePoint = ch.codePointAt(0);
  return codePoint !== void 0 && isCodePointInRanges(codePoint, lineBreakNumericAffixRanges);
}
function endsWithLineBreakNumericAffix(text) {
  const last = getLastSignificantCodePoint(text);
  return last !== null && isLineBreakNumericAffix(last);
}
function startsWithDecimalDigit(text) {
  const first = getFirstSignificantCodePoint(text);
  return first !== null && decimalDigitRe.test(first);
}
function splitTrailingForwardStickyCluster(text) {
  let splitIndex = text.length;
  while (splitIndex > 0) {
    const start = previousCodePointStart(text, splitIndex);
    const ch = text.slice(start, splitIndex);
    if (combiningMarkRe.test(ch) || kinsokuEnd.has(ch) || forwardStickyGlue.has(ch)) {
      splitIndex = start;
      continue;
    }
    break;
  }
  if (splitIndex <= 0 || splitIndex === text.length)
    return null;
  return {
    head: text.slice(0, splitIndex),
    tail: text.slice(splitIndex)
  };
}
function getRepeatableSingleCharRunChar(text, isWordLike, kind) {
  return kind === "text" && !isWordLike && text.length === 1 && text !== "-" && text !== "\u2014" ? text : null;
}
function hasArabicNoSpacePunctuation(containsArabic, lastCodePoint) {
  return containsArabic && lastCodePoint !== null && arabicNoSpaceTrailingPunctuation.has(lastCodePoint);
}
function endsWithMyanmarMedialGlue(segment2) {
  const lastCodePoint = getLastCodePoint(segment2);
  return lastCodePoint !== null && myanmarMedialGlue.has(lastCodePoint);
}
function splitLeadingSpaceAndMarks(segment2) {
  if (segment2.length < 2 || segment2[0] !== " ")
    return null;
  const marks = segment2.slice(1);
  if (new RegExp("^\\p{M}+$", "u").test(marks)) {
    return { space: " ", marks };
  }
  return null;
}
function endsWithClosingQuote(text) {
  let end = text.length;
  while (end > 0) {
    const start = previousCodePointStart(text, end);
    const ch = text.slice(start, end);
    if (closingQuoteChars.has(ch))
      return true;
    if (!leftStickyPunctuation.has(ch))
      return false;
    end = start;
  }
  return false;
}
function classifySegmentBreakChar(ch, whiteSpace) {
  if (whiteSpace === "pre-wrap") {
    if (ch === " ")
      return "preserved-space";
    if (ch === "	")
      return "tab";
    if (ch === "\n")
      return "hard-break";
  }
  if (ch === " ")
    return "space";
  if (ch === "\xA0" || ch === "\u202F" || ch === "\u2060" || ch === "\uFEFF") {
    return "glue";
  }
  if (ch === "\u200B")
    return "zero-width-break";
  if (ch === "\xAD")
    return "soft-hyphen";
  return "text";
}
var breakCharRe = /[\x20\t\n\xA0\xAD\u200B\u202F\u2060\uFEFF]/;
function joinTextParts(parts) {
  return parts.length === 1 ? parts[0] : parts.join("");
}
function joinReversedPrefixParts(prefixParts, tail) {
  const parts = [];
  for (let i = prefixParts.length - 1; i >= 0; i--) {
    parts.push(prefixParts[i]);
  }
  parts.push(tail);
  return joinTextParts(parts);
}
function splitSegmentByBreakKind(segment2, isWordLike, start, whiteSpace) {
  if (!breakCharRe.test(segment2)) {
    return [{ text: segment2, isWordLike, kind: "text", start }];
  }
  const pieces = [];
  let currentKind = null;
  let currentStart = 0;
  let currentWordLike = false;
  let offset = 0;
  for (const ch of segment2) {
    const kind = classifySegmentBreakChar(ch, whiteSpace);
    const wordLike = kind === "text" && isWordLike;
    if (currentKind !== null && kind === currentKind && wordLike === currentWordLike) {
      offset += ch.length;
      continue;
    }
    if (currentKind !== null) {
      pieces.push({
        text: segment2.slice(currentStart, offset),
        isWordLike: currentWordLike,
        kind: currentKind,
        start: start + currentStart
      });
    }
    currentKind = kind;
    currentStart = offset;
    currentWordLike = wordLike;
    offset += ch.length;
  }
  if (currentKind !== null) {
    pieces.push({
      text: segment2.slice(currentStart),
      isWordLike: currentWordLike,
      kind: currentKind,
      start: start + currentStart
    });
  }
  return pieces;
}
function isTextRunBoundary(kind) {
  return kind === "space" || kind === "preserved-space" || kind === "zero-width-break" || kind === "hard-break";
}
var urlSchemeSegmentRe = /^[A-Za-z][A-Za-z0-9+.-]*:$/;
function isUrlLikeRunStart(segmentation, index) {
  const text = segmentation.texts[index];
  if (text.startsWith("www."))
    return true;
  return urlSchemeSegmentRe.test(text) && index + 1 < segmentation.len && segmentation.kinds[index + 1] === "text" && segmentation.texts[index + 1] === "//";
}
function isUrlQueryBoundarySegment(text) {
  return text.includes("?") && (text.includes("://") || text.startsWith("www."));
}
function mergeUrlRuns(segmentation, normalized, profile) {
  const texts = [];
  const isWordLike = [];
  const kinds = [];
  const starts = [];
  for (let i = 0; i < segmentation.len; i++) {
    const start = segmentation.starts[i];
    let text = segmentation.texts[i];
    let wordLike = segmentation.isWordLike[i];
    const kind = segmentation.kinds[i];
    let queryStartOverride = -1;
    if (kind === "text" && isUrlLikeRunStart(segmentation, i)) {
      const urlParts = [text];
      let j2 = i + 1;
      while (j2 < segmentation.len && !isTextRunBoundary(segmentation.kinds[j2]) && numericAffixBoundary(normalized, segmentation.starts[j2], profile) !== false) {
        if (queryStartOverride < 0 && isUrlLikeRunStart(segmentation, j2)) {
          queryStartOverride = segmentation.starts[j2];
        }
        const nextText = segmentation.texts[j2];
        urlParts.push(nextText);
        wordLike = true;
        j2++;
        if (nextText.includes("?"))
          break;
      }
      text = joinTextParts(urlParts);
      i = j2 - 1;
    }
    texts.push(text);
    isWordLike.push(wordLike);
    kinds.push(kind);
    starts.push(start);
    if (!isUrlQueryBoundarySegment(text))
      continue;
    const nextIndex = i + 1;
    if (nextIndex >= segmentation.len || isTextRunBoundary(segmentation.kinds[nextIndex])) {
      continue;
    }
    const queryParts = [];
    const queryStart = queryStartOverride < 0 ? segmentation.starts[nextIndex] : queryStartOverride;
    let j = nextIndex;
    while (j < segmentation.len && !isTextRunBoundary(segmentation.kinds[j]) && numericAffixBoundary(normalized, segmentation.starts[j], profile) !== false) {
      queryParts.push(segmentation.texts[j]);
      j++;
    }
    if (queryParts.length > 0) {
      texts.push(joinTextParts(queryParts));
      isWordLike.push(true);
      kinds.push("text");
      starts.push(queryStart);
      i = j - 1;
    }
  }
  return {
    len: texts.length,
    texts,
    isWordLike,
    kinds,
    starts
  };
}
var numericJoinerChars = /* @__PURE__ */ new Set([
  ":",
  "-",
  "/",
  "\xD7",
  ",",
  ".",
  "+",
  "\u2013",
  "\u2014"
]);
var wordInternalSymbolRe = /[\p{P}\p{S}\p{Co}]/u;
var emojiPresentationRe = new RegExp("\\p{Emoji_Presentation}", "u");
var noSpaceWordBreakAfterChars = /* @__PURE__ */ new Set([
  "?",
  "\u058A",
  "-",
  "\u2010",
  "\u2012",
  "\u2013",
  "\u2014",
  "\u2026",
  "\u203C",
  "\u203D",
  "\u2049"
]);
function isAsciiWordInternalSymbolCode(code) {
  return code >= 33 && code <= 47 && code !== 45 || code >= 58 && code <= 64 && code !== 63 || code >= 91 && code <= 96 || code >= 123 && code <= 126;
}
function isNoSpaceWordInternalSymbol(ch) {
  const code = ch.charCodeAt(0);
  if (code < 128)
    return isAsciiWordInternalSymbolCode(code);
  return !noSpaceWordBreakAfterChars.has(ch) && !emojiPresentationRe.test(ch) && wordInternalSymbolRe.test(ch);
}
function isNoSpaceWordInternalSymbolSegment(text) {
  let sawSymbol = false;
  for (const ch of text) {
    if (combiningMarkRe.test(ch))
      continue;
    if (!isNoSpaceWordInternalSymbol(ch))
      return false;
    sawSymbol = true;
  }
  return sawSymbol;
}
function endsWithNoSpaceWordJoiner(text) {
  for (let end = text.length; end > 0; ) {
    const start = previousCodePointStart(text, end);
    const ch = text.slice(start, end);
    if (combiningMarkRe.test(ch)) {
      end = start;
      continue;
    }
    return isNoSpaceWordInternalSymbol(ch) || isLineBreakNumericAffix(ch);
  }
  return false;
}
var asciiAlphabeticBoundaryRe = /[A-Za-z#&*<=>@^_`~]/;
function isAsciiBoundary(left, right) {
  return left.charCodeAt(0) < 128 && right.charCodeAt(0) < 128;
}
function numericAffixBoundary(source, boundary, profile) {
  if (!profile.geckoAsciiLineBreaks || boundary <= 0 || boundary >= source.length)
    return null;
  const left = getLastSignificantCodePoint(source, boundary);
  const right = String.fromCodePoint(source.codePointAt(boundary));
  if (left === null || !isAsciiBoundary(left, right))
    return null;
  const leftAffix = isLineBreakNumericAffix(left);
  const rightAffix = isLineBreakNumericAffix(right);
  if (!leftAffix && !rightAffix)
    return null;
  if (right === ")" || right === "]" || right === "}" || "!,.:;?/".includes(right))
    return true;
  if ("([{".includes(left) || left === '"' || left === "'" || right === '"' || right === "'")
    return true;
  if (right === "|" || right === "-")
    return true;
  if (leftAffix && asciiAlphabeticBoundaryRe.test(right) || asciiAlphabeticBoundaryRe.test(left) && rightAffix)
    return true;
  if (rightAffix && (")]}".includes(left) || /[0-9]/.test(left)))
    return true;
  if (leftAffix && ("([{".includes(right) || /[0-9]/.test(right)))
    return true;
  return false;
}
function openingPunctuationJoinsPrevious(left, right, profile, leftEnd = left.length) {
  const first = right[0];
  if (first === void 0 || !"([{".includes(first))
    return null;
  const last = getLastSignificantCodePoint(left, leftEnd);
  if (last === null)
    return null;
  if (profile.geckoAsciiLineBreaks && isAsciiBoundary(last, first)) {
    return asciiAlphabeticBoundaryRe.test(last) || decimalDigitRe.test(last) || `"'([{`.includes(last) || isLineBreakNumericAffix(last);
  }
  if (last.charCodeAt(0) >= 128) {
    return !isCJK2(last) && /[\p{L}\p{N}]/u.test(last) ? true : null;
  }
  return /[A-Za-z0-9]/.test(last) || "$'(/<@[^_`{".includes(last);
}
function canJoinNoSpaceWordBoundary(leftText, leftWordLike, rightText, rightWordLike, profile) {
  if (rightText[0] === "-" && isCJK2(leftText))
    return true;
  if (isCJK2(leftText) || isCJK2(rightText))
    return false;
  const openingJoin = openingPunctuationJoinsPrevious(leftText, rightText, profile);
  if (openingJoin !== null)
    return openingJoin;
  const leftSymbol = !leftWordLike && isNoSpaceWordInternalSymbolSegment(leftText);
  const rightSymbol = !rightWordLike && isNoSpaceWordInternalSymbolSegment(rightText);
  const leftAffix = endsWithLineBreakNumericAffix(leftText);
  const leftEndsJoiner = (leftWordLike || leftAffix) && endsWithNoSpaceWordJoiner(leftText);
  if (!leftSymbol && !rightSymbol && !leftEndsJoiner)
    return false;
  return (leftWordLike || leftSymbol || leftAffix) && (rightWordLike || rightSymbol);
}
function segmentContainsDecimalDigit(text) {
  for (const ch of text) {
    if (decimalDigitRe.test(ch))
      return true;
  }
  return false;
}
function isNumericRunSegment(text) {
  if (text.length === 0)
    return false;
  for (const ch of text) {
    if (decimalDigitRe.test(ch) || numericJoinerChars.has(ch))
      continue;
    return false;
  }
  return true;
}
function mergeNumericRuns(segmentation, normalized, profile) {
  const texts = [];
  const isWordLike = [];
  const kinds = [];
  const starts = [];
  function pushNumericRun(text, start) {
    if (text.includes("-")) {
      const parts = text.split("-");
      let shouldSplit = parts.length > 1;
      for (let i = 0; i < parts.length; i++) {
        const part = parts[i];
        if (!shouldSplit)
          break;
        if (part.length === 0 || !segmentContainsDecimalDigit(part) || !isNumericRunSegment(part)) {
          shouldSplit = false;
        }
      }
      if (shouldSplit) {
        let offset = 0;
        for (let i = 0; i < parts.length; i++) {
          const part = parts[i];
          const splitText = i < parts.length - 1 ? `${part}-` : part;
          texts.push(splitText);
          isWordLike.push(true);
          kinds.push("text");
          starts.push(start + offset);
          offset += splitText.length;
        }
        return;
      }
    }
    texts.push(text);
    isWordLike.push(true);
    kinds.push("text");
    starts.push(start);
  }
  for (let i = 0; i < segmentation.len; i++) {
    const text = segmentation.texts[i];
    const kind = segmentation.kinds[i];
    if (kind === "text" && isNumericRunSegment(text) && segmentContainsDecimalDigit(text)) {
      const mergedParts = [text];
      let j = i + 1;
      while (j < segmentation.len && segmentation.kinds[j] === "text" && isNumericRunSegment(segmentation.texts[j]) && numericAffixBoundary(normalized, segmentation.starts[j], profile) !== false) {
        mergedParts.push(segmentation.texts[j]);
        j++;
      }
      pushNumericRun(joinTextParts(mergedParts), segmentation.starts[i]);
      i = j - 1;
      continue;
    }
    texts.push(text);
    isWordLike.push(segmentation.isWordLike[i]);
    kinds.push(kind);
    starts.push(segmentation.starts[i]);
  }
  return {
    len: texts.length,
    texts,
    isWordLike,
    kinds,
    starts
  };
}
function mergeNoSpaceWordChains(segmentation, normalized, profile) {
  const texts = [];
  const isWordLike = [];
  const kinds = [];
  const starts = [];
  let i = 0;
  while (i < segmentation.len) {
    const text = segmentation.texts[i];
    const kind = segmentation.kinds[i];
    const wordLike = segmentation.isWordLike[i];
    if (kind === "text") {
      const mergedParts = [text];
      let j = i + 1;
      let mergedWordLike = wordLike;
      while (j < segmentation.len && segmentation.kinds[j] === "text" && (numericAffixBoundary(normalized, segmentation.starts[j], profile) ?? canJoinNoSpaceWordBoundary(segmentation.texts[j - 1], segmentation.isWordLike[j - 1], segmentation.texts[j], segmentation.isWordLike[j], profile))) {
        const nextText = segmentation.texts[j];
        mergedParts.push(nextText);
        mergedWordLike = mergedWordLike || segmentation.isWordLike[j];
        j++;
      }
      if (j > i + 1) {
        texts.push(joinTextParts(mergedParts));
        isWordLike.push(mergedWordLike);
        kinds.push("text");
        starts.push(segmentation.starts[i]);
        i = j;
        continue;
      }
    }
    texts.push(text);
    isWordLike.push(wordLike);
    kinds.push(kind);
    starts.push(segmentation.starts[i]);
    i++;
  }
  return {
    len: texts.length,
    texts,
    isWordLike,
    kinds,
    starts
  };
}
function mergeGlueConnectedTextRuns(segmentation) {
  const texts = [];
  const isWordLike = [];
  const kinds = [];
  const starts = [];
  let read = 0;
  while (read < segmentation.len) {
    const textParts = [segmentation.texts[read]];
    let wordLike = segmentation.isWordLike[read];
    let kind = segmentation.kinds[read];
    let start = segmentation.starts[read];
    if (kind === "glue") {
      const glueParts = [textParts[0]];
      const glueStart = start;
      read++;
      while (read < segmentation.len && segmentation.kinds[read] === "glue") {
        glueParts.push(segmentation.texts[read]);
        read++;
      }
      const glueText = joinTextParts(glueParts);
      if (read < segmentation.len && segmentation.kinds[read] === "text") {
        textParts[0] = glueText;
        textParts.push(segmentation.texts[read]);
        wordLike = segmentation.isWordLike[read];
        kind = "text";
        start = glueStart;
        read++;
      } else {
        texts.push(glueText);
        isWordLike.push(false);
        kinds.push("glue");
        starts.push(glueStart);
        continue;
      }
    } else {
      read++;
    }
    if (kind === "text") {
      while (read < segmentation.len && segmentation.kinds[read] === "glue") {
        const glueParts = [];
        while (read < segmentation.len && segmentation.kinds[read] === "glue") {
          glueParts.push(segmentation.texts[read]);
          read++;
        }
        const glueText = joinTextParts(glueParts);
        if (read < segmentation.len && segmentation.kinds[read] === "text") {
          textParts.push(glueText, segmentation.texts[read]);
          wordLike = wordLike || segmentation.isWordLike[read];
          read++;
          continue;
        }
        textParts.push(glueText);
      }
    }
    texts.push(joinTextParts(textParts));
    isWordLike.push(wordLike);
    kinds.push(kind);
    starts.push(start);
  }
  return {
    len: texts.length,
    texts,
    isWordLike,
    kinds,
    starts
  };
}
function carryTrailingForwardStickyAcrossCJKBoundary(segmentation) {
  const { texts, kinds, starts } = segmentation;
  for (let i = 0; i < texts.length - 1; i++) {
    if (kinds[i] !== "text" || kinds[i + 1] !== "text")
      continue;
    if (!isCJK2(texts[i]) || !isCJK2(texts[i + 1]))
      continue;
    const split = splitTrailingForwardStickyCluster(texts[i]);
    if (split === null)
      continue;
    texts[i] = split.head;
    texts[i + 1] = split.tail + texts[i + 1];
    starts[i + 1] = starts[i] + split.head.length;
  }
}
function buildMergedSegmentation(normalized, profile, whiteSpace) {
  const wordSegmenter = getSharedWordSegmenter();
  let mergedLen = 0;
  const mergedTexts = [];
  const mergedWordLike = [];
  const mergedKinds = [];
  const mergedStarts = [];
  let hasTail = false;
  let tailStart = 0;
  let tailEnd = 0;
  let tailWordLike = false;
  let tailKind = "text";
  let tailSingleCharRunChar = null;
  let tailContainsCJK = false;
  let tailContainsArabicScript = false;
  let tailEndsWithClosingQuote = false;
  let tailEndsWithMyanmarMedialGlue = false;
  let tailHasArabicNoSpacePunctuation = false;
  for (const s of wordSegmenter.segment(normalized)) {
    for (const piece of splitSegmentByBreakKind(s.segment, s.isWordLike ?? false, s.index, whiteSpace)) {
      const isText = piece.kind === "text";
      const repeatableSingleCharRunChar = getRepeatableSingleCharRunChar(piece.text, piece.isWordLike, piece.kind);
      const pieceContainsCJK = isCJK2(piece.text);
      const pieceContainsArabicScript = containsArabicScript(piece.text);
      const pieceLastCodePoint = getLastCodePoint(piece.text);
      const pieceEndsWithClosingQuote = endsWithClosingQuote(piece.text);
      const pieceEndsWithMyanmarMedialGlue = endsWithMyanmarMedialGlue(piece.text);
      const pieceEnd = piece.start + piece.text.length;
      const boundaryJoin = numericAffixBoundary(normalized, piece.start, profile) ?? (tailContainsCJK || pieceContainsCJK ? null : openingPunctuationJoinsPrevious(normalized, piece.text, profile, piece.start));
      let appendToTail = false;
      if (profile.carryCJKAfterClosingQuote && isText && hasTail && tailKind === "text" && pieceContainsCJK && tailContainsCJK && tailEndsWithClosingQuote) {
        appendToTail = true;
      } else if (isText && hasTail && tailKind === "text" && isCJKLineStartProhibitedSegment(piece.text) && tailContainsCJK) {
        appendToTail = true;
      } else if (isText && hasTail && tailKind === "text" && tailEndsWithMyanmarMedialGlue) {
        appendToTail = true;
      } else if (isText && hasTail && tailKind === "text" && piece.isWordLike && pieceContainsArabicScript && tailHasArabicNoSpacePunctuation) {
        appendToTail = true;
      } else if (repeatableSingleCharRunChar !== null && hasTail && tailKind === "text" && tailSingleCharRunChar === repeatableSingleCharRunChar && boundaryJoin !== false) {
        tailEnd = pieceEnd;
        continue;
      } else if (isText && !piece.isWordLike && hasTail && tailKind === "text" && !tailContainsCJK && (isLeftStickyPunctuationSegment(piece.text) || piece.text === "-" && tailWordLike)) {
        appendToTail = true;
      }
      if (isText && hasTail && tailKind === "text" && boundaryJoin !== null)
        appendToTail = boundaryJoin;
      if (appendToTail) {
        tailEnd = pieceEnd;
        tailWordLike = tailWordLike || piece.isWordLike;
        tailSingleCharRunChar = null;
        tailContainsCJK = tailContainsCJK || pieceContainsCJK;
        tailContainsArabicScript = tailContainsArabicScript || pieceContainsArabicScript;
        tailEndsWithClosingQuote = pieceEndsWithClosingQuote;
        tailEndsWithMyanmarMedialGlue = pieceEndsWithMyanmarMedialGlue;
        tailHasArabicNoSpacePunctuation = hasArabicNoSpacePunctuation(tailContainsArabicScript, pieceLastCodePoint);
      } else {
        if (hasTail) {
          mergedTexts[mergedLen] = normalized.slice(tailStart, tailEnd);
          mergedWordLike[mergedLen] = tailWordLike;
          mergedKinds[mergedLen] = tailKind;
          mergedStarts[mergedLen] = tailStart;
          mergedLen++;
        }
        hasTail = true;
        tailStart = piece.start;
        tailEnd = pieceEnd;
        tailWordLike = piece.isWordLike;
        tailKind = piece.kind;
        tailSingleCharRunChar = repeatableSingleCharRunChar;
        tailContainsCJK = pieceContainsCJK;
        tailContainsArabicScript = pieceContainsArabicScript;
        tailEndsWithClosingQuote = pieceEndsWithClosingQuote;
        tailEndsWithMyanmarMedialGlue = pieceEndsWithMyanmarMedialGlue;
        tailHasArabicNoSpacePunctuation = hasArabicNoSpacePunctuation(pieceContainsArabicScript, pieceLastCodePoint);
      }
    }
  }
  if (hasTail) {
    mergedTexts[mergedLen] = normalized.slice(tailStart, tailEnd);
    mergedWordLike[mergedLen] = tailWordLike;
    mergedKinds[mergedLen] = tailKind;
    mergedStarts[mergedLen] = tailStart;
    mergedLen++;
  }
  for (let i = 1; i < mergedLen; i++) {
    if (mergedKinds[i] === "text" && !mergedWordLike[i] && isPunctuationGlueCluster(mergedTexts[i]) && mergedKinds[i - 1] === "text" && !isCJK2(mergedTexts[i - 1]) && (numericAffixBoundary(normalized, mergedStarts[i], profile) ?? openingPunctuationJoinsPrevious(normalized, mergedTexts[i], profile, mergedStarts[i])) !== false) {
      mergedTexts[i - 1] += mergedTexts[i];
      mergedWordLike[i - 1] = mergedWordLike[i - 1] || mergedWordLike[i];
      mergedTexts[i] = "";
    }
  }
  let nextLiveIndex = -1;
  let forwardStickyPrefixParts = null;
  for (let i = mergedLen - 1; i >= 0; i--) {
    const text = mergedTexts[i];
    if (text.length === 0)
      continue;
    const nextText = forwardStickyPrefixParts?.at(-1) ?? (nextLiveIndex >= 0 ? mergedTexts[nextLiveIndex] : null);
    if (mergedKinds[i] === "text" && !mergedWordLike[i] && nextText !== null && mergedKinds[nextLiveIndex] === "text" && ((numericAffixBoundary(normalized, mergedStarts[i] + text.length, profile) ?? (isForwardStickyClusterSegment(text) && openingPunctuationJoinsPrevious(text, nextText, profile) !== false)) || text === "-" && startsWithDecimalDigit(nextText))) {
      if (forwardStickyPrefixParts === null)
        forwardStickyPrefixParts = [];
      forwardStickyPrefixParts.push(text);
      mergedStarts[nextLiveIndex] = mergedStarts[i];
      mergedTexts[i] = "";
      continue;
    }
    if (forwardStickyPrefixParts !== null) {
      mergedTexts[nextLiveIndex] = joinReversedPrefixParts(forwardStickyPrefixParts, mergedTexts[nextLiveIndex]);
      forwardStickyPrefixParts = null;
    }
    nextLiveIndex = i;
  }
  if (forwardStickyPrefixParts !== null) {
    mergedTexts[nextLiveIndex] = joinReversedPrefixParts(forwardStickyPrefixParts, mergedTexts[nextLiveIndex]);
  }
  let compactLen = 0;
  for (let read = 0; read < mergedLen; read++) {
    const text = mergedTexts[read];
    if (text.length === 0)
      continue;
    if (compactLen !== read) {
      mergedTexts[compactLen] = text;
      mergedWordLike[compactLen] = mergedWordLike[read];
      mergedKinds[compactLen] = mergedKinds[read];
      mergedStarts[compactLen] = mergedStarts[read];
    }
    compactLen++;
  }
  mergedTexts.length = compactLen;
  mergedWordLike.length = compactLen;
  mergedKinds.length = compactLen;
  mergedStarts.length = compactLen;
  const compacted = mergeGlueConnectedTextRuns({
    len: compactLen,
    texts: mergedTexts,
    isWordLike: mergedWordLike,
    kinds: mergedKinds,
    starts: mergedStarts
  });
  const mergedRuns = mergeNoSpaceWordChains(mergeNumericRuns(mergeUrlRuns(compacted, normalized, profile), normalized, profile), normalized, profile);
  carryTrailingForwardStickyAcrossCJKBoundary(mergedRuns);
  for (let i = 0; i < mergedRuns.len - 1; i++) {
    const split = splitLeadingSpaceAndMarks(mergedRuns.texts[i]);
    if (split === null)
      continue;
    if (mergedRuns.kinds[i] !== "space" && mergedRuns.kinds[i] !== "preserved-space" || mergedRuns.kinds[i + 1] !== "text" || !containsArabicScript(mergedRuns.texts[i + 1])) {
      continue;
    }
    mergedRuns.texts[i] = split.space;
    mergedRuns.isWordLike[i] = false;
    mergedRuns.kinds[i] = mergedRuns.kinds[i] === "preserved-space" ? "preserved-space" : "space";
    mergedRuns.texts[i + 1] = split.marks + mergedRuns.texts[i + 1];
    mergedRuns.starts[i + 1] = mergedRuns.starts[i] + split.space.length;
  }
  return mergedRuns;
}
function mergeKeepAllTextSegments(normalized, segmentation, profile) {
  if (segmentation.len <= 1)
    return segmentation;
  const texts = [];
  const isWordLike = [];
  const kinds = [];
  const starts = [];
  let groupStart = -1;
  let groupContainsCJK = false;
  function pushOriginalText(index) {
    texts.push(segmentation.texts[index]);
    isWordLike.push(segmentation.isWordLike[index]);
    kinds.push("text");
    starts.push(segmentation.starts[index]);
  }
  function pushMergedText(start, end) {
    let wordLike = false;
    for (let i = start; i < end; i++) {
      wordLike = wordLike || segmentation.isWordLike[i];
    }
    const sourceStart = segmentation.starts[start];
    const sourceEnd = end < segmentation.len ? segmentation.starts[end] : normalized.length;
    texts.push(normalized.slice(sourceStart, sourceEnd));
    isWordLike.push(wordLike);
    kinds.push("text");
    starts.push(sourceStart);
  }
  function flushGroup(end) {
    if (groupStart < 0)
      return;
    if (groupContainsCJK) {
      if (groupStart + 1 === end) {
        pushOriginalText(groupStart);
      } else {
        pushMergedText(groupStart, end);
      }
    } else {
      for (let i = groupStart; i < end; i++)
        pushOriginalText(i);
    }
    groupStart = -1;
    groupContainsCJK = false;
  }
  for (let i = 0; i < segmentation.len; i++) {
    const text = segmentation.texts[i];
    const kind = segmentation.kinds[i];
    if (kind === "text") {
      if (groupStart >= 0 && (!canContinueKeepAllTextRun(segmentation.texts[i - 1], profile.breakKeepAllAfterPunctuation) || numericAffixBoundary(normalized, segmentation.starts[i], profile) === false)) {
        flushGroup(i);
      }
      if (groupStart < 0)
        groupStart = i;
      groupContainsCJK = groupContainsCJK || isCJK2(text);
      continue;
    }
    flushGroup(i);
    texts.push(text);
    isWordLike.push(segmentation.isWordLike[i]);
    kinds.push(kind);
    starts.push(segmentation.starts[i]);
  }
  flushGroup(segmentation.len);
  return {
    len: texts.length,
    texts,
    isWordLike,
    kinds,
    starts
  };
}
function isNumericHyphen(text, index) {
  const next = text.charCodeAt(index + 1);
  if (next < 128) {
    if (next < 48 || next > 57)
      return false;
  } else {
    const codePoint = text.codePointAt(index + 1);
    if (codePoint === void 0 || !decimalDigitRe.test(String.fromCodePoint(codePoint)))
      return false;
  }
  for (let end = index; end > 0; ) {
    const start = previousCodePointStart(text, end);
    const previous = text.slice(start, end);
    if (!combiningMarkRe.test(previous))
      return isCJK2(previous) || !/[\p{L}\p{N}]/u.test(previous);
    end = start;
  }
  return true;
}
function buildBaseCjkUnits(segText, profile) {
  const units = [];
  let unitStart = 0;
  let unitEnd = 0;
  let unitContainsCJK = false;
  let unitEndsWithClosingQuote = false;
  let unitIsSingleKinsokuEnd = false;
  let unitHasHyphen = false;
  let unitHasNumericHyphen = false;
  function pushUnit() {
    if (unitEnd === unitStart)
      return;
    units.push({
      text: segText.slice(unitStart, unitEnd),
      start: unitStart,
      overflow: unitContainsCJK ? unitHasHyphen ? "grapheme" : "none" : "word-like"
    });
    unitStart = unitEnd;
    unitContainsCJK = false;
    unitEndsWithClosingQuote = false;
    unitIsSingleKinsokuEnd = false;
    unitHasHyphen = false;
    unitHasNumericHyphen = false;
  }
  function startUnit(grapheme, start, graphemeContainsCJK) {
    unitStart = start;
    unitEnd = start + grapheme.length;
    unitContainsCJK = graphemeContainsCJK;
    unitHasHyphen = grapheme === "-";
    unitEndsWithClosingQuote = endsWithClosingQuote(grapheme);
    unitIsSingleKinsokuEnd = kinsokuEnd.has(grapheme);
  }
  function appendToUnit(grapheme, graphemeContainsCJK) {
    unitEnd += grapheme.length;
    unitContainsCJK = unitContainsCJK || graphemeContainsCJK;
    unitHasHyphen = unitHasHyphen || grapheme === "-";
    const graphemeEndsWithClosingQuote = endsWithClosingQuote(grapheme);
    if (grapheme.length === 1 && leftStickyPunctuation.has(grapheme)) {
      unitEndsWithClosingQuote = unitEndsWithClosingQuote || graphemeEndsWithClosingQuote;
    } else {
      unitEndsWithClosingQuote = graphemeEndsWithClosingQuote;
    }
    unitIsSingleKinsokuEnd = false;
  }
  for (const gs of getSharedGraphemeSegmenter().segment(segText)) {
    const grapheme = gs.segment;
    const graphemeContainsCJK = isCJK2(grapheme);
    if (unitEnd === unitStart) {
      startUnit(grapheme, gs.index, graphemeContainsCJK);
      continue;
    }
    const attachHyphen = grapheme === "-" && unitContainsCJK;
    if (attachHyphen && isNumericHyphen(segText, gs.index))
      unitHasNumericHyphen = true;
    if (unitIsSingleKinsokuEnd || kinsokuStart.has(grapheme) || leftStickyPunctuation.has(grapheme) || attachHyphen || unitHasNumericHyphen && !graphemeContainsCJK || profile.carryCJKAfterClosingQuote && graphemeContainsCJK && unitEndsWithClosingQuote) {
      appendToUnit(grapheme, graphemeContainsCJK);
      continue;
    }
    if (!unitContainsCJK && !graphemeContainsCJK) {
      appendToUnit(grapheme, graphemeContainsCJK);
      continue;
    }
    pushUnit();
    startUnit(grapheme, gs.index, graphemeContainsCJK);
  }
  pushUnit();
  return units;
}
function mergeKeepAllTextUnits(segText, units, profile) {
  if (units.length <= 1)
    return units;
  const merged = [];
  let groupStart = -1;
  let groupContainsCJK = false;
  function pushMergedUnit(start, end) {
    const sourceStart = units[start].start;
    const sourceEnd = end < units.length ? units[end].start : segText.length;
    merged.push({
      text: segText.slice(sourceStart, sourceEnd),
      start: sourceStart,
      overflow: "word-like"
    });
  }
  function flushGroup(end) {
    if (groupStart < 0)
      return;
    if (groupContainsCJK) {
      if (groupStart + 1 === end) {
        merged.push(units[groupStart]);
      } else {
        pushMergedUnit(groupStart, end);
      }
    } else {
      for (let i = groupStart; i < end; i++)
        merged.push(units[i]);
    }
    groupStart = -1;
    groupContainsCJK = false;
  }
  for (let i = 0; i < units.length; i++) {
    const unit = units[i];
    if (groupStart >= 0 && (!canContinueKeepAllTextRun(units[i - 1].text, profile.breakKeepAllAfterPunctuation) || numericAffixBoundary(segText, unit.start, profile) === false)) {
      flushGroup(i);
    }
    if (groupStart < 0)
      groupStart = i;
    groupContainsCJK = groupContainsCJK || isCJK2(unit.text);
  }
  flushGroup(units.length);
  return merged;
}
function getCjkTextUnits(text, profile, wordBreak) {
  const units = buildBaseCjkUnits(text, profile);
  return wordBreak === "keep-all" ? mergeKeepAllTextUnits(text, units, profile) : units;
}
function isPreferredBreakGrapheme(grapheme) {
  return grapheme === "-" || grapheme === "\u058A" || grapheme === "\u2010" || grapheme === "\u2012" || grapheme === "\u2013" || grapheme === "\u2014";
}
function isIndependentSymbolRun(text) {
  if (text.length === 0 || new RegExp("\\p{Cf}", "u").test(text))
    return false;
  for (const { segment: segment2 } of getSharedGraphemeSegmenter().segment(text)) {
    const base = String.fromCodePoint(segment2.codePointAt(0));
    if (!/[\p{P}\p{S}]/u.test(base) || emojiPresentationRe.test(base) || segment2.includes("\uFE0F") || new RegExp("\\p{Emoji_Modifier}", "u").test(base))
      return false;
  }
  return true;
}
function getBreakablePreferredBreaks(text) {
  if (!/[-\u058A\u2010\u2012\u2013\u2014]/u.test(text))
    return null;
  const breaks = [];
  let graphemeIndex = 0;
  for (const gs of getSharedGraphemeSegmenter().segment(text)) {
    graphemeIndex++;
    const numericSign = gs.segment === "-" && isNumericHyphen(text, gs.index);
    if (isPreferredBreakGrapheme(gs.segment) && !numericSign)
      breaks.push(graphemeIndex);
  }
  return breaks.length === 0 ? null : breaks;
}
function analyzeText(text, profile, whiteSpace = "normal", wordBreak = "normal") {
  const normalized = whiteSpace === "pre-wrap" ? normalizeWhitespacePreWrap(text) : normalizeWhitespaceNormal(text);
  if (normalized.length === 0) {
    return {
      normalized,
      len: 0,
      texts: [],
      isWordLike: [],
      kinds: [],
      starts: []
    };
  }
  const mergedSegmentation = buildMergedSegmentation(normalized, profile, whiteSpace);
  const segmentation = wordBreak === "keep-all" ? mergeKeepAllTextSegments(normalized, mergedSegmentation, profile) : mergedSegmentation;
  return {
    normalized,
    ...segmentation
  };
}

// scripts/folia/node_modules/@chenglou/pretext/dist/measurement.js
var measureContext = null;
var segmentMetricCaches = /* @__PURE__ */ new Map();
var cachedEngineProfile = null;
var MAX_PREFIX_FIT_GRAPHEMES = 96;
var emojiPresentationRe2 = new RegExp("\\p{Emoji_Presentation}", "u");
var maybeEmojiRe = /[\p{Emoji_Presentation}\p{Extended_Pictographic}\p{Regional_Indicator}\uFE0F\u20E3]/u;
var emojiCorrectionCache = /* @__PURE__ */ new Map();
function getMeasureContext() {
  if (measureContext !== null)
    return measureContext;
  if (typeof OffscreenCanvas !== "undefined") {
    measureContext = new OffscreenCanvas(1, 1).getContext("2d");
    return measureContext;
  }
  if (typeof document !== "undefined") {
    measureContext = document.createElement("canvas").getContext("2d");
    return measureContext;
  }
  throw new Error("Text measurement requires OffscreenCanvas or a DOM canvas context.");
}
function getSegmentMetricCache(font) {
  let cache2 = segmentMetricCaches.get(font);
  if (!cache2) {
    cache2 = /* @__PURE__ */ new Map();
    segmentMetricCaches.set(font, cache2);
  }
  return cache2;
}
function getSegmentMetrics(seg, cache2) {
  let metrics = cache2.get(seg);
  if (metrics === void 0) {
    const ctx = getMeasureContext();
    metrics = {
      width: ctx.measureText(seg).width
    };
    cache2.set(seg, metrics);
  }
  return metrics;
}
function getEngineProfile() {
  if (cachedEngineProfile !== null)
    return cachedEngineProfile;
  if (typeof navigator === "undefined") {
    cachedEngineProfile = {
      geckoAsciiLineBreaks: false,
      lineFitEpsilon: 5e-3,
      carryCJKAfterClosingQuote: false,
      breakKeepAllAfterPunctuation: true,
      preferPrefixWidthsForBreakableRuns: false
    };
    return cachedEngineProfile;
  }
  const ua = navigator.userAgent;
  const vendor = navigator.vendor;
  const isSafari = vendor === "Apple Computer, Inc." && ua.includes("Safari/") && !ua.includes("Chrome/") && !ua.includes("Chromium/") && !ua.includes("CriOS/") && !ua.includes("FxiOS/") && !ua.includes("EdgiOS/");
  const isChromium = ua.includes("Chrome/") || ua.includes("Chromium/") || ua.includes("CriOS/") || ua.includes("Edg/");
  const isGecko = ua.includes("Firefox/") && !ua.includes("FxiOS/");
  cachedEngineProfile = {
    geckoAsciiLineBreaks: isGecko,
    lineFitEpsilon: isSafari ? 1 / 64 : 5e-3,
    carryCJKAfterClosingQuote: isChromium,
    breakKeepAllAfterPunctuation: !isSafari,
    preferPrefixWidthsForBreakableRuns: isSafari
  };
  return cachedEngineProfile;
}
function parseFontSize(font) {
  const m = font.match(/(?:^|\D)(\d+(?:\.\d+)?)\s*px/);
  return m ? parseFloat(m[1]) : 16;
}
function isEmojiGrapheme(g) {
  return emojiPresentationRe2.test(g) || g.includes("\uFE0F");
}
function textMayContainEmoji(text) {
  return maybeEmojiRe.test(text);
}
function getEmojiCorrection(font) {
  let correction = emojiCorrectionCache.get(font);
  if (correction !== void 0)
    return correction;
  const fontSize = parseFontSize(font);
  const ctx = getMeasureContext();
  ctx.font = font;
  const canvasW = ctx.measureText("\u{1F600}").width;
  correction = 0;
  if (canvasW > fontSize + 0.5 && typeof document !== "undefined" && document.body !== null) {
    const span = document.createElement("span");
    span.style.font = font;
    span.style.display = "inline-block";
    span.style.visibility = "hidden";
    span.style.position = "absolute";
    span.textContent = "\u{1F600}";
    document.body.appendChild(span);
    const domW = span.getBoundingClientRect().width;
    document.body.removeChild(span);
    if (canvasW - domW > 0.5) {
      correction = canvasW - domW;
    }
  }
  emojiCorrectionCache.set(font, correction);
  return correction;
}
function countEmojiGraphemes(text) {
  let count = 0;
  const graphemeSegmenter2 = getSharedGraphemeSegmenter();
  for (const g of graphemeSegmenter2.segment(text)) {
    if (isEmojiGrapheme(g.segment))
      count++;
  }
  return count;
}
function getEmojiCount(seg, metrics) {
  if (metrics.emojiCount === void 0) {
    metrics.emojiCount = countEmojiGraphemes(seg);
  }
  return metrics.emojiCount;
}
function getCorrectedSegmentWidth(seg, metrics, emojiCorrection) {
  if (emojiCorrection === 0)
    return metrics.width;
  return metrics.width - getEmojiCount(seg, metrics) * emojiCorrection;
}
function getSegmentBreakableFitAdvances(seg, metrics, cache2, emojiCorrection, mode) {
  if (metrics.breakableFitAdvances !== void 0 && metrics.breakableFitMode === mode) {
    return metrics.breakableFitAdvances;
  }
  metrics.breakableFitMode = mode;
  const graphemeSegmenter2 = getSharedGraphemeSegmenter();
  const graphemes = [];
  for (const gs of graphemeSegmenter2.segment(seg)) {
    graphemes.push(gs.segment);
  }
  if (graphemes.length <= 1) {
    metrics.breakableFitAdvances = null;
    return metrics.breakableFitAdvances;
  }
  if (mode === "sum-graphemes") {
    const advances2 = [];
    for (const grapheme of graphemes) {
      const graphemeMetrics = getSegmentMetrics(grapheme, cache2);
      advances2.push(getCorrectedSegmentWidth(grapheme, graphemeMetrics, emojiCorrection));
    }
    metrics.breakableFitAdvances = advances2;
    return metrics.breakableFitAdvances;
  }
  if (mode === "pair-context" || graphemes.length > MAX_PREFIX_FIT_GRAPHEMES) {
    const advances2 = [];
    let previousGrapheme = null;
    let previousWidth = 0;
    for (const grapheme of graphemes) {
      const graphemeMetrics = getSegmentMetrics(grapheme, cache2);
      const currentWidth = getCorrectedSegmentWidth(grapheme, graphemeMetrics, emojiCorrection);
      if (previousGrapheme === null) {
        advances2.push(currentWidth);
      } else {
        const pair = previousGrapheme + grapheme;
        const pairMetrics = getSegmentMetrics(pair, cache2);
        advances2.push(getCorrectedSegmentWidth(pair, pairMetrics, emojiCorrection) - previousWidth);
      }
      previousGrapheme = grapheme;
      previousWidth = currentWidth;
    }
    metrics.breakableFitAdvances = advances2;
    return metrics.breakableFitAdvances;
  }
  const advances = [];
  let prefix = "";
  let prefixWidth = 0;
  for (const grapheme of graphemes) {
    prefix += grapheme;
    const prefixMetrics = getSegmentMetrics(prefix, cache2);
    const nextPrefixWidth = getCorrectedSegmentWidth(prefix, prefixMetrics, emojiCorrection);
    advances.push(nextPrefixWidth - prefixWidth);
    prefixWidth = nextPrefixWidth;
  }
  metrics.breakableFitAdvances = advances;
  return metrics.breakableFitAdvances;
}
function getFontMeasurementState(font, needsEmojiCorrection) {
  const ctx = getMeasureContext();
  ctx.font = font;
  const cache2 = getSegmentMetricCache(font);
  const emojiCorrection = needsEmojiCorrection ? getEmojiCorrection(font) : 0;
  return { cache: cache2, emojiCorrection };
}

// scripts/folia/node_modules/@chenglou/pretext/dist/line-break.js
function isDiscretionaryLineEnd(kinds, endSegmentIndex, endGraphemeIndex) {
  return endGraphemeIndex === 0 && endSegmentIndex > 0 && endSegmentIndex < kinds.length && kinds[endSegmentIndex - 1] === "soft-hyphen";
}
function consumesAtLineStart(kind) {
  return kind === "space" || kind === "zero-width-break" || kind === "soft-hyphen";
}
function breaksAfter(kind) {
  return kind === "space" || kind === "preserved-space" || kind === "tab" || kind === "zero-width-break" || kind === "soft-hyphen";
}
function normalizeLineStartSegmentIndex(prepared, segmentIndex, endSegmentIndex = prepared.widths.length) {
  while (segmentIndex < endSegmentIndex) {
    const kind = prepared.kinds[segmentIndex];
    if (!consumesAtLineStart(kind))
      break;
    segmentIndex++;
  }
  return segmentIndex;
}
function getTabAdvance(lineWidth, tabStopAdvance) {
  if (tabStopAdvance <= 0)
    return 0;
  const remainder = lineWidth % tabStopAdvance;
  if (Math.abs(remainder) <= 1e-6)
    return tabStopAdvance;
  return tabStopAdvance - remainder;
}
function getLeadingLetterSpacing(prepared, hasContent, segmentIndex) {
  return prepared.letterSpacing !== 0 && hasContent && prepared.spacingGraphemeCounts[segmentIndex] > 0 ? prepared.letterSpacing : 0;
}
function getLineEndContribution(leadingSpacing, segmentContribution) {
  return segmentContribution === 0 ? 0 : leadingSpacing + segmentContribution;
}
function getTabTrailingLetterSpacing(prepared, segmentIndex) {
  return prepared.letterSpacing !== 0 && prepared.spacingGraphemeCounts[segmentIndex] > 0 ? prepared.letterSpacing : 0;
}
function getWholeSegmentFitContribution(prepared, kind, segmentIndex, leadingSpacing, segmentWidth) {
  const segmentContribution = kind === "tab" ? segmentWidth + getTabTrailingLetterSpacing(prepared, segmentIndex) : prepared.lineEndFitAdvances[segmentIndex];
  return getLineEndContribution(leadingSpacing, segmentContribution);
}
function getBreakOpportunityFitContribution(prepared, kind, segmentIndex, leadingSpacing) {
  const segmentContribution = kind === "tab" ? 0 : prepared.lineEndFitAdvances[segmentIndex];
  return getLineEndContribution(leadingSpacing, segmentContribution);
}
function getLineEndPaintContribution(prepared, kind, segmentIndex, leadingSpacing, segmentWidth) {
  const segmentContribution = kind === "tab" ? segmentWidth : prepared.lineEndPaintAdvances[segmentIndex];
  return getLineEndContribution(leadingSpacing, segmentContribution);
}
function getBreakableGraphemeAdvance(prepared, hasContent, baseAdvance) {
  return prepared.letterSpacing !== 0 && hasContent ? baseAdvance + prepared.letterSpacing : baseAdvance;
}
function getBreakableCandidateFitWidth(prepared, candidatePaintWidth) {
  return prepared.letterSpacing === 0 ? candidatePaintWidth : candidatePaintWidth + prepared.letterSpacing;
}
function getNextPreferredBreakIndex(preferredBreaks, preferredBreakIndex, graphemeEnd) {
  let lo = preferredBreakIndex;
  if (lo >= preferredBreaks.length || preferredBreaks[lo] >= graphemeEnd)
    return lo;
  let hi = preferredBreaks.length;
  lo++;
  while (lo < hi) {
    const mid = Math.floor((lo + hi) / 2);
    if (preferredBreaks[mid] < graphemeEnd)
      lo = mid + 1;
    else
      hi = mid;
  }
  return lo;
}
function getTerminalLetterSpacing(prepared, startSegmentIndex, startGraphemeIndex, endSegmentIndex, endGraphemeIndex) {
  if (prepared.letterSpacing === 0)
    return 0;
  if (endGraphemeIndex > 0) {
    return prepared.spacingGraphemeCounts[endSegmentIndex] > 0 ? prepared.letterSpacing : 0;
  }
  if (isDiscretionaryLineEnd(prepared.kinds, endSegmentIndex, endGraphemeIndex))
    return 0;
  for (let i = endSegmentIndex - 1; i >= startSegmentIndex; i--) {
    const kind = prepared.kinds[i];
    if (kind === "space" || kind === "zero-width-break" || kind === "hard-break" || kind === "soft-hyphen")
      continue;
    if (i === startSegmentIndex && startGraphemeIndex > 0) {
      return prepared.letterSpacing;
    }
    return prepared.spacingGraphemeCounts[i] > 0 ? prepared.letterSpacing : 0;
  }
  return 0;
}
function finalizeLinePaintWidth(prepared, width, startSegmentIndex, startGraphemeIndex, endSegmentIndex, endGraphemeIndex) {
  return width + getTerminalLetterSpacing(prepared, startSegmentIndex, startGraphemeIndex, endSegmentIndex, endGraphemeIndex);
}
function findChunkIndexForStart(prepared, segmentIndex) {
  let lo = 0;
  let hi = prepared.chunks.length;
  while (lo < hi) {
    const mid = Math.floor((lo + hi) / 2);
    if (segmentIndex < prepared.chunks[mid].consumedEndSegmentIndex) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  return lo < prepared.chunks.length ? lo : -1;
}
function normalizeLineStartInChunk(prepared, chunkIndex, cursor) {
  let segmentIndex = cursor.segmentIndex;
  if (cursor.graphemeIndex > 0)
    return chunkIndex;
  for (let currentChunkIndex = chunkIndex; currentChunkIndex < prepared.chunks.length; currentChunkIndex++) {
    const chunk = prepared.chunks[currentChunkIndex];
    if (chunk.startSegmentIndex === chunk.endSegmentIndex && segmentIndex === chunk.startSegmentIndex) {
      cursor.segmentIndex = segmentIndex;
      cursor.graphemeIndex = 0;
      return currentChunkIndex;
    }
    if (segmentIndex < chunk.startSegmentIndex)
      segmentIndex = chunk.startSegmentIndex;
    segmentIndex = normalizeLineStartSegmentIndex(prepared, segmentIndex, chunk.endSegmentIndex);
    if (segmentIndex < chunk.endSegmentIndex) {
      cursor.segmentIndex = segmentIndex;
      cursor.graphemeIndex = 0;
      return currentChunkIndex;
    }
    if (chunk.consumedEndSegmentIndex >= prepared.widths.length)
      return -1;
    segmentIndex = chunk.consumedEndSegmentIndex;
    cursor.segmentIndex = segmentIndex;
    cursor.graphemeIndex = 0;
  }
  return -1;
}
function normalizePreparedLineStart(prepared, cursor) {
  if (cursor.segmentIndex >= prepared.widths.length)
    return -1;
  const chunkIndex = findChunkIndexForStart(prepared, cursor.segmentIndex);
  if (chunkIndex < 0)
    return -1;
  return normalizeLineStartInChunk(prepared, chunkIndex, cursor);
}
function normalizeLineStartChunkIndexFromHint(prepared, chunkIndex, cursor) {
  if (cursor.segmentIndex >= prepared.widths.length)
    return -1;
  let nextChunkIndex = chunkIndex;
  while (nextChunkIndex < prepared.chunks.length && cursor.segmentIndex >= prepared.chunks[nextChunkIndex].consumedEndSegmentIndex) {
    nextChunkIndex++;
  }
  if (nextChunkIndex >= prepared.chunks.length)
    return -1;
  return normalizeLineStartInChunk(prepared, nextChunkIndex, cursor);
}
function walkPreparedLinesSimple(prepared, maxWidth, onLine) {
  const { widths, kinds, breakableFitAdvances, breakablePreferredBreaks } = prepared;
  if (widths.length === 0)
    return 0;
  const engineProfile = getEngineProfile();
  const lineFitEpsilon = engineProfile.lineFitEpsilon;
  const fitLimit = maxWidth + lineFitEpsilon;
  let lineCount = 0;
  let lineW = 0;
  let hasContent = false;
  let lineStartSegmentIndex = 0;
  let lineStartGraphemeIndex = 0;
  let lineEndSegmentIndex = 0;
  let lineEndGraphemeIndex = 0;
  let pendingBreakSegmentIndex = -1;
  let pendingBreakPaintWidth = 0;
  function clearPendingBreak() {
    pendingBreakSegmentIndex = -1;
    pendingBreakPaintWidth = 0;
  }
  function emitCurrentLine(endSegmentIndex = lineEndSegmentIndex, endGraphemeIndex = lineEndGraphemeIndex, width = lineW) {
    lineCount++;
    onLine?.(width, lineStartSegmentIndex, lineStartGraphemeIndex, endSegmentIndex, endGraphemeIndex);
    lineW = 0;
    hasContent = false;
    clearPendingBreak();
  }
  function startLineAtSegment(segmentIndex, width) {
    hasContent = true;
    lineStartSegmentIndex = segmentIndex;
    lineStartGraphemeIndex = 0;
    lineEndSegmentIndex = segmentIndex + 1;
    lineEndGraphemeIndex = 0;
    lineW = width;
  }
  function startLineAtGrapheme(segmentIndex, graphemeIndex, width) {
    hasContent = true;
    lineStartSegmentIndex = segmentIndex;
    lineStartGraphemeIndex = graphemeIndex;
    lineEndSegmentIndex = segmentIndex;
    lineEndGraphemeIndex = graphemeIndex + 1;
    lineW = width;
  }
  function appendWholeSegment(segmentIndex, width) {
    if (!hasContent) {
      startLineAtSegment(segmentIndex, width);
      return;
    }
    lineW += width;
    lineEndSegmentIndex = segmentIndex + 1;
    lineEndGraphemeIndex = 0;
  }
  function appendBreakableSegmentFrom(segmentIndex, startGraphemeIndex) {
    const fitAdvances = breakableFitAdvances[segmentIndex];
    const preferredBreaks = breakablePreferredBreaks[segmentIndex] ?? null;
    let preferredBreakIndex = preferredBreaks === null ? -1 : getNextPreferredBreakIndex(preferredBreaks, 0, startGraphemeIndex + 1);
    let lastPreferredBreakEnd = -1;
    let lastPreferredBreakWidth = 0;
    let g = startGraphemeIndex;
    while (g < fitAdvances.length) {
      const gw = fitAdvances[g];
      if (!hasContent) {
        startLineAtGrapheme(segmentIndex, g, gw);
      } else if (lineW + gw > fitLimit) {
        if (preferredBreaks !== null && lastPreferredBreakEnd > startGraphemeIndex) {
          emitCurrentLine(segmentIndex, lastPreferredBreakEnd, lastPreferredBreakWidth);
          g = lastPreferredBreakEnd;
          preferredBreakIndex = getNextPreferredBreakIndex(preferredBreaks, preferredBreakIndex, g + 1);
          lastPreferredBreakEnd = -1;
          lastPreferredBreakWidth = 0;
          continue;
        }
        emitCurrentLine();
        startLineAtGrapheme(segmentIndex, g, gw);
      } else {
        lineW += gw;
        lineEndSegmentIndex = segmentIndex;
        lineEndGraphemeIndex = g + 1;
      }
      const graphemeEnd = g + 1;
      if (preferredBreaks !== null && preferredBreaks[preferredBreakIndex] === graphemeEnd) {
        lastPreferredBreakEnd = graphemeEnd;
        lastPreferredBreakWidth = lineW;
        preferredBreakIndex++;
      }
      g++;
    }
    if (hasContent && lineEndSegmentIndex === segmentIndex && lineEndGraphemeIndex === fitAdvances.length) {
      lineEndSegmentIndex = segmentIndex + 1;
      lineEndGraphemeIndex = 0;
    }
  }
  let i = 0;
  while (i < widths.length) {
    if (!hasContent) {
      i = normalizeLineStartSegmentIndex(prepared, i);
      if (i >= widths.length)
        break;
    }
    const w = widths[i];
    const kind = kinds[i];
    const breakAfter = breaksAfter(kind);
    if (!hasContent) {
      if (w > fitLimit && breakableFitAdvances[i] !== null) {
        appendBreakableSegmentFrom(i, 0);
      } else {
        startLineAtSegment(i, w);
      }
      if (breakAfter) {
        pendingBreakSegmentIndex = i + 1;
        pendingBreakPaintWidth = lineW - w;
      }
      i++;
      continue;
    }
    const newW = lineW + w;
    if (newW > fitLimit) {
      if (breakAfter) {
        appendWholeSegment(i, w);
        emitCurrentLine(i + 1, 0, lineW - w);
        i++;
        continue;
      }
      if (pendingBreakSegmentIndex >= 0) {
        if (lineEndSegmentIndex > pendingBreakSegmentIndex || lineEndSegmentIndex === pendingBreakSegmentIndex && lineEndGraphemeIndex > 0) {
          emitCurrentLine();
          continue;
        }
        emitCurrentLine(pendingBreakSegmentIndex, 0, pendingBreakPaintWidth);
        continue;
      }
      if (w > fitLimit && breakableFitAdvances[i] !== null) {
        emitCurrentLine();
        appendBreakableSegmentFrom(i, 0);
        i++;
        continue;
      }
      emitCurrentLine();
      continue;
    }
    appendWholeSegment(i, w);
    if (breakAfter) {
      pendingBreakSegmentIndex = i + 1;
      pendingBreakPaintWidth = lineW - w;
    }
    i++;
  }
  if (hasContent)
    emitCurrentLine();
  return lineCount;
}
function walkPreparedLinesRaw(prepared, maxWidth, onLine) {
  if (prepared.simpleLineWalkFastPath)
    return walkPreparedLinesSimple(prepared, maxWidth, onLine);
  const cursor = { segmentIndex: 0, graphemeIndex: 0 };
  const chunkIndex = normalizePreparedLineStart(prepared, cursor);
  return walkPreparedComplexLines(prepared, cursor, chunkIndex, maxWidth, onLine).lineCount;
}
function stepPreparedChunkLineGeometry(prepared, cursor, chunkIndex, maxWidth) {
  return walkPreparedComplexLines(prepared, cursor, chunkIndex, maxWidth, void 0, 1).lastLineWidth;
}
function walkPreparedComplexLines(prepared, cursor, chunkIndex, maxWidth, onLine, lineLimit = Number.POSITIVE_INFINITY) {
  const { widths, kinds, breakableFitAdvances, breakablePreferredBreaks, discretionaryHyphenWidth } = prepared;
  const engineProfile = getEngineProfile();
  const lineFitEpsilon = engineProfile.lineFitEpsilon;
  const fitLimit = maxWidth + lineFitEpsilon;
  let lineStartSegmentIndex;
  let lineStartGraphemeIndex;
  let lineW;
  let hasContent;
  let lineEndSegmentIndex;
  let lineEndGraphemeIndex;
  let pendingBreakSegmentIndex;
  let pendingBreakFitWidth;
  let pendingBreakPaintWidth;
  let pendingBreakKind;
  function getCurrentLinePaintWidth() {
    return pendingBreakKind === "soft-hyphen" && pendingBreakSegmentIndex === lineEndSegmentIndex && lineEndGraphemeIndex === 0 ? pendingBreakPaintWidth : lineW;
  }
  function finishLine(endSegmentIndex = lineEndSegmentIndex, endGraphemeIndex = lineEndGraphemeIndex, width = getCurrentLinePaintWidth()) {
    if (!hasContent)
      return null;
    cursor.segmentIndex = endSegmentIndex;
    cursor.graphemeIndex = endGraphemeIndex;
    return finalizeLinePaintWidth(prepared, width, lineStartSegmentIndex, lineStartGraphemeIndex, endSegmentIndex, endGraphemeIndex);
  }
  function startLineAtSegment(segmentIndex, width) {
    hasContent = true;
    lineEndSegmentIndex = segmentIndex + 1;
    lineEndGraphemeIndex = 0;
    lineW = width;
  }
  function startLineAtGrapheme(segmentIndex, graphemeIndex, width) {
    hasContent = true;
    lineEndSegmentIndex = segmentIndex;
    lineEndGraphemeIndex = graphemeIndex + 1;
    lineW = width;
  }
  function appendWholeSegment(segmentIndex, advance) {
    if (!hasContent) {
      startLineAtSegment(segmentIndex, advance);
      return;
    }
    lineW += advance;
    lineEndSegmentIndex = segmentIndex + 1;
    lineEndGraphemeIndex = 0;
  }
  function updatePendingBreakForWholeSegment(kind, breakAfter, segmentIndex, segmentWidth, leadingSpacing, advance) {
    if (!breakAfter)
      return;
    const fitAdvance = getBreakOpportunityFitContribution(prepared, kind, segmentIndex, leadingSpacing);
    const paintAdvance = getLineEndPaintContribution(prepared, kind, segmentIndex, leadingSpacing, segmentWidth);
    pendingBreakSegmentIndex = segmentIndex + 1;
    pendingBreakFitWidth = lineW - advance + fitAdvance;
    pendingBreakPaintWidth = lineW - advance + paintAdvance;
    pendingBreakKind = kind;
  }
  function appendBreakableSegmentFrom(segmentIndex, startGraphemeIndex) {
    const fitAdvances = breakableFitAdvances[segmentIndex];
    const preferredBreaks = breakablePreferredBreaks[segmentIndex] ?? null;
    let preferredBreakIndex = preferredBreaks === null ? -1 : getNextPreferredBreakIndex(preferredBreaks, 0, startGraphemeIndex + 1);
    let lastPreferredBreakEnd = -1;
    let lastPreferredBreakWidth = 0;
    for (let g = startGraphemeIndex; g < fitAdvances.length; g++) {
      const baseGw = fitAdvances[g];
      if (!hasContent) {
        startLineAtGrapheme(segmentIndex, g, baseGw);
      } else {
        const gw = getBreakableGraphemeAdvance(prepared, true, baseGw);
        const candidatePaintWidth = lineW + gw;
        if (getBreakableCandidateFitWidth(prepared, candidatePaintWidth) > fitLimit) {
          if (preferredBreaks !== null && lastPreferredBreakEnd > startGraphemeIndex) {
            return finishLine(segmentIndex, lastPreferredBreakEnd, lastPreferredBreakWidth);
          }
          return finishLine();
        }
        lineW = candidatePaintWidth;
        lineEndSegmentIndex = segmentIndex;
        lineEndGraphemeIndex = g + 1;
      }
      const graphemeEnd = g + 1;
      if (preferredBreaks !== null && preferredBreaks[preferredBreakIndex] === graphemeEnd) {
        lastPreferredBreakEnd = graphemeEnd;
        lastPreferredBreakWidth = lineW;
        preferredBreakIndex++;
      }
    }
    if (hasContent && lineEndSegmentIndex === segmentIndex && lineEndGraphemeIndex === fitAdvances.length) {
      lineEndSegmentIndex = segmentIndex + 1;
      lineEndGraphemeIndex = 0;
    }
    return null;
  }
  let lineCount = 0;
  let lastLineWidth = null;
  while (chunkIndex >= 0 && lineCount < lineLimit) {
    lineStartSegmentIndex = cursor.segmentIndex;
    lineStartGraphemeIndex = cursor.graphemeIndex;
    lineW = 0;
    hasContent = false;
    lineEndSegmentIndex = cursor.segmentIndex;
    lineEndGraphemeIndex = cursor.graphemeIndex;
    pendingBreakSegmentIndex = -1;
    pendingBreakFitWidth = 0;
    pendingBreakPaintWidth = 0;
    pendingBreakKind = null;
    const chunk = prepared.chunks[chunkIndex];
    let lineWidth = null;
    if (chunk.startSegmentIndex === chunk.endSegmentIndex) {
      cursor.segmentIndex = chunk.consumedEndSegmentIndex;
      cursor.graphemeIndex = 0;
      lineWidth = 0;
    } else {
      lineLoop: for (let i = cursor.segmentIndex; i < chunk.endSegmentIndex; i++) {
        const kind = kinds[i];
        const breakAfter = breaksAfter(kind);
        const startGraphemeIndex = i === cursor.segmentIndex ? cursor.graphemeIndex : 0;
        const leadingSpacing = getLeadingLetterSpacing(prepared, hasContent, i);
        const w = kind === "tab" ? getTabAdvance(lineW + leadingSpacing, prepared.tabStopAdvance) : widths[i];
        const advance = leadingSpacing + w;
        const fitAdvance = getWholeSegmentFitContribution(prepared, kind, i, leadingSpacing, w);
        if (kind === "soft-hyphen" && startGraphemeIndex === 0) {
          if (hasContent) {
            lineEndSegmentIndex = i + 1;
            lineEndGraphemeIndex = 0;
            if (i + 1 < chunk.endSegmentIndex) {
              pendingBreakSegmentIndex = i + 1;
              pendingBreakFitWidth = lineW + discretionaryHyphenWidth;
              pendingBreakPaintWidth = lineW + discretionaryHyphenWidth;
              pendingBreakKind = kind;
            }
          }
          continue;
        }
        if (!hasContent) {
          if (startGraphemeIndex > 0) {
            const line2 = appendBreakableSegmentFrom(i, startGraphemeIndex);
            if (line2 !== null) {
              lineWidth = line2;
              break lineLoop;
            }
          } else if (fitAdvance > fitLimit && breakableFitAdvances[i] !== null) {
            const line2 = appendBreakableSegmentFrom(i, 0);
            if (line2 !== null) {
              lineWidth = line2;
              break lineLoop;
            }
          } else {
            startLineAtSegment(i, w);
          }
          updatePendingBreakForWholeSegment(kind, breakAfter, i, w, leadingSpacing, advance);
          continue;
        }
        const newFitW = lineW + fitAdvance;
        if (newFitW > fitLimit) {
          const currentBreakFitWidth = lineW + getBreakOpportunityFitContribution(prepared, kind, i, leadingSpacing);
          const currentBreakPaintWidth = lineW + getLineEndPaintContribution(prepared, kind, i, leadingSpacing, w);
          if (breakAfter && currentBreakFitWidth <= fitLimit) {
            appendWholeSegment(i, advance);
            lineWidth = finishLine(i + 1, 0, currentBreakPaintWidth);
            break lineLoop;
          }
          if (pendingBreakSegmentIndex >= 0 && pendingBreakFitWidth <= fitLimit) {
            if (lineEndSegmentIndex > pendingBreakSegmentIndex || lineEndSegmentIndex === pendingBreakSegmentIndex && lineEndGraphemeIndex > 0) {
              lineWidth = finishLine();
              break lineLoop;
            }
            lineWidth = finishLine(pendingBreakSegmentIndex, 0, pendingBreakPaintWidth);
            break lineLoop;
          }
          lineWidth = finishLine();
          break lineLoop;
        }
        appendWholeSegment(i, advance);
        updatePendingBreakForWholeSegment(kind, breakAfter, i, w, leadingSpacing, advance);
      }
      if (lineWidth === null) {
        lineWidth = pendingBreakSegmentIndex === chunk.consumedEndSegmentIndex && lineEndGraphemeIndex === 0 ? finishLine(chunk.consumedEndSegmentIndex, 0, pendingBreakPaintWidth) : finishLine(chunk.consumedEndSegmentIndex, 0, lineW);
      }
    }
    if (lineWidth === null)
      break;
    lastLineWidth = lineWidth;
    lineCount++;
    onLine?.(lineWidth, lineStartSegmentIndex, lineStartGraphemeIndex, cursor.segmentIndex, cursor.graphemeIndex);
    if (lineCount < lineLimit)
      chunkIndex = normalizeLineStartChunkIndexFromHint(prepared, chunkIndex, cursor);
  }
  return { lineCount, lastLineWidth };
}
function stepPreparedSimpleLineGeometry(prepared, cursor, maxWidth) {
  const { widths, kinds, breakableFitAdvances, breakablePreferredBreaks } = prepared;
  const engineProfile = getEngineProfile();
  const lineFitEpsilon = engineProfile.lineFitEpsilon;
  const fitLimit = maxWidth + lineFitEpsilon;
  let lineW = 0;
  let hasContent = false;
  let lineEndSegmentIndex = cursor.segmentIndex;
  let lineEndGraphemeIndex = cursor.graphemeIndex;
  let pendingBreakSegmentIndex = -1;
  let pendingBreakPaintWidth = 0;
  for (let i = cursor.segmentIndex; i < widths.length; i++) {
    const kind = kinds[i];
    const breakAfter = breaksAfter(kind);
    const startGraphemeIndex = i === cursor.segmentIndex ? cursor.graphemeIndex : 0;
    const breakableFitAdvance = breakableFitAdvances[i];
    const w = widths[i];
    if (!hasContent) {
      if (startGraphemeIndex > 0 || w > fitLimit && breakableFitAdvance !== null) {
        const fitAdvances = breakableFitAdvance;
        const preferredBreaks = breakablePreferredBreaks[i] ?? null;
        let preferredBreakIndex = preferredBreaks === null ? -1 : getNextPreferredBreakIndex(preferredBreaks, 0, startGraphemeIndex + 1);
        let lastPreferredBreakEnd = -1;
        let lastPreferredBreakWidth = 0;
        const firstGraphemeWidth = fitAdvances[startGraphemeIndex];
        hasContent = true;
        lineW = firstGraphemeWidth;
        lineEndSegmentIndex = i;
        lineEndGraphemeIndex = startGraphemeIndex + 1;
        if (preferredBreaks !== null && preferredBreaks[preferredBreakIndex] === lineEndGraphemeIndex) {
          lastPreferredBreakEnd = lineEndGraphemeIndex;
          lastPreferredBreakWidth = lineW;
          preferredBreakIndex++;
        }
        for (let g = startGraphemeIndex + 1; g < fitAdvances.length; g++) {
          const gw = fitAdvances[g];
          if (lineW + gw > fitLimit) {
            if (preferredBreaks !== null && lastPreferredBreakEnd > startGraphemeIndex) {
              cursor.segmentIndex = i;
              cursor.graphemeIndex = lastPreferredBreakEnd;
              return lastPreferredBreakWidth;
            }
            cursor.segmentIndex = lineEndSegmentIndex;
            cursor.graphemeIndex = lineEndGraphemeIndex;
            return lineW;
          }
          lineW += gw;
          lineEndSegmentIndex = i;
          lineEndGraphemeIndex = g + 1;
          if (preferredBreaks !== null && preferredBreaks[preferredBreakIndex] === lineEndGraphemeIndex) {
            lastPreferredBreakEnd = lineEndGraphemeIndex;
            lastPreferredBreakWidth = lineW;
            preferredBreakIndex++;
          }
        }
        if (lineEndSegmentIndex === i && lineEndGraphemeIndex === fitAdvances.length) {
          lineEndSegmentIndex = i + 1;
          lineEndGraphemeIndex = 0;
        }
      } else {
        hasContent = true;
        lineW = w;
        lineEndSegmentIndex = i + 1;
        lineEndGraphemeIndex = 0;
      }
      if (breakAfter) {
        pendingBreakSegmentIndex = i + 1;
        pendingBreakPaintWidth = lineW - w;
      }
      continue;
    }
    if (lineW + w > fitLimit) {
      if (breakAfter) {
        cursor.segmentIndex = i + 1;
        cursor.graphemeIndex = 0;
        return lineW;
      }
      if (pendingBreakSegmentIndex >= 0) {
        if (lineEndSegmentIndex > pendingBreakSegmentIndex || lineEndSegmentIndex === pendingBreakSegmentIndex && lineEndGraphemeIndex > 0) {
          cursor.segmentIndex = lineEndSegmentIndex;
          cursor.graphemeIndex = lineEndGraphemeIndex;
          return lineW;
        }
        cursor.segmentIndex = pendingBreakSegmentIndex;
        cursor.graphemeIndex = 0;
        return pendingBreakPaintWidth;
      }
      cursor.segmentIndex = lineEndSegmentIndex;
      cursor.graphemeIndex = lineEndGraphemeIndex;
      return lineW;
    }
    lineW += w;
    lineEndSegmentIndex = i + 1;
    lineEndGraphemeIndex = 0;
    if (breakAfter) {
      pendingBreakSegmentIndex = i + 1;
      pendingBreakPaintWidth = lineW - w;
    }
  }
  if (!hasContent)
    return null;
  cursor.segmentIndex = lineEndSegmentIndex;
  cursor.graphemeIndex = lineEndGraphemeIndex;
  return lineW;
}
function stepPreparedLineGeometryFromChunk(prepared, cursor, chunkIndex, maxWidth) {
  if (prepared.simpleLineWalkFastPath) {
    return stepPreparedSimpleLineGeometry(prepared, cursor, maxWidth);
  }
  return stepPreparedChunkLineGeometry(prepared, cursor, chunkIndex, maxWidth);
}
function stepPreparedLineGeometry(prepared, cursor, maxWidth) {
  const chunkIndex = normalizePreparedLineStart(prepared, cursor);
  if (chunkIndex < 0)
    return null;
  return stepPreparedLineGeometryFromChunk(prepared, cursor, chunkIndex, maxWidth);
}

// scripts/folia/node_modules/@chenglou/pretext/dist/layout.js
function createEmptyPrepared(includeSegments) {
  if (includeSegments) {
    return {
      widths: [],
      lineEndFitAdvances: [],
      lineEndPaintAdvances: [],
      kinds: [],
      simpleLineWalkFastPath: true,
      segLevels: null,
      breakableFitAdvances: [],
      breakablePreferredBreaks: [],
      letterSpacing: 0,
      spacingGraphemeCounts: [],
      discretionaryHyphenWidth: 0,
      tabStopAdvance: 0,
      chunks: [],
      segments: []
    };
  }
  return {
    widths: [],
    lineEndFitAdvances: [],
    lineEndPaintAdvances: [],
    kinds: [],
    simpleLineWalkFastPath: true,
    segLevels: null,
    breakableFitAdvances: [],
    breakablePreferredBreaks: [],
    letterSpacing: 0,
    spacingGraphemeCounts: [],
    discretionaryHyphenWidth: 0,
    tabStopAdvance: 0,
    chunks: []
  };
}
function countRenderedSpacingGraphemes(text, kind) {
  if (kind === "zero-width-break" || kind === "soft-hyphen" || kind === "hard-break") {
    return 0;
  }
  if (kind === "tab")
    return 1;
  let count = 0;
  const graphemeSegmenter2 = getSharedGraphemeSegmenter();
  for (const _ of graphemeSegmenter2.segment(text))
    count++;
  return count;
}
function addInternalLetterSpacing(width, graphemeCount, letterSpacing) {
  return graphemeCount > 1 ? width + (graphemeCount - 1) * letterSpacing : width;
}
function measureAnalysis(analysis, font, includeSegments, wordBreak, letterSpacing) {
  const engineProfile = getEngineProfile();
  const { cache: cache2, emojiCorrection } = getFontMeasurementState(font, textMayContainEmoji(analysis.normalized));
  const discretionaryHyphenWidth = getCorrectedSegmentWidth("-", getSegmentMetrics("-", cache2), emojiCorrection) + (letterSpacing === 0 ? 0 : letterSpacing * 2);
  const spaceWidth = getCorrectedSegmentWidth(" ", getSegmentMetrics(" ", cache2), emojiCorrection);
  const tabStopAdvance = spaceWidth * 8;
  const hasLetterSpacing = letterSpacing !== 0;
  if (analysis.len === 0)
    return createEmptyPrepared(includeSegments);
  const widths = [];
  const lineEndFitAdvances = [];
  const lineEndPaintAdvances = [];
  const kinds = [];
  let simpleLineWalkFastPath = !hasLetterSpacing;
  const segStarts = includeSegments ? [] : null;
  const breakableFitAdvances = [];
  const breakablePreferredBreaks = [];
  const spacingGraphemeCounts = [];
  const segments = includeSegments ? [] : null;
  const chunks = [];
  let chunkStartSegmentIndex = 0;
  function pushMeasuredSegment(text, width, lineEndFitAdvance, lineEndPaintAdvance, kind, start, breakableFitAdvance, breakablePreferredBreak, spacingGraphemeCount) {
    if (kind !== "text" && kind !== "space" && kind !== "zero-width-break") {
      simpleLineWalkFastPath = false;
    }
    widths.push(width);
    lineEndFitAdvances.push(lineEndFitAdvance);
    lineEndPaintAdvances.push(lineEndPaintAdvance);
    kinds.push(kind);
    segStarts?.push(start);
    breakableFitAdvances.push(breakableFitAdvance);
    breakablePreferredBreaks.push(breakablePreferredBreak);
    if (hasLetterSpacing)
      spacingGraphemeCounts.push(spacingGraphemeCount);
    if (segments !== null)
      segments.push(text);
  }
  function pushMeasuredTextSegment(text, textMetrics, kind, start, allowOverflowBreaks) {
    const spacingGraphemeCount = hasLetterSpacing ? countRenderedSpacingGraphemes(text, kind) : 0;
    const width = addInternalLetterSpacing(getCorrectedSegmentWidth(text, textMetrics, emojiCorrection), spacingGraphemeCount, letterSpacing);
    const baseLineEndFitAdvance = kind === "space" || kind === "preserved-space" || kind === "zero-width-break" ? 0 : width;
    const lineEndFitAdvance = baseLineEndFitAdvance === 0 ? 0 : baseLineEndFitAdvance + (spacingGraphemeCount > 0 ? letterSpacing : 0);
    const lineEndPaintAdvance = kind === "space" || kind === "zero-width-break" ? 0 : width;
    if (allowOverflowBreaks && text.length > 1) {
      let fitMode = "sum-graphemes";
      if (letterSpacing !== 0) {
        fitMode = "segment-prefixes";
      } else if (isNumericRunSegment(text)) {
        fitMode = "pair-context";
      } else if (engineProfile.preferPrefixWidthsForBreakableRuns) {
        fitMode = "segment-prefixes";
      }
      const fitAdvances = getSegmentBreakableFitAdvances(text, textMetrics, cache2, emojiCorrection, fitMode);
      const preferredBreaks = fitAdvances === null || wordBreak === "keep-all" ? null : getBreakablePreferredBreaks(text);
      pushMeasuredSegment(text, width, lineEndFitAdvance, lineEndPaintAdvance, kind, start, fitAdvances, preferredBreaks, spacingGraphemeCount);
      return;
    }
    pushMeasuredSegment(text, width, lineEndFitAdvance, lineEndPaintAdvance, kind, start, null, null, spacingGraphemeCount);
  }
  for (let mi = 0; mi < analysis.len; mi++) {
    const segText = analysis.texts[mi];
    const segKind = analysis.kinds[mi];
    const segStart = analysis.starts[mi];
    if (segKind === "soft-hyphen") {
      pushMeasuredSegment(segText, 0, discretionaryHyphenWidth, discretionaryHyphenWidth, segKind, segStart, null, null, 0);
      continue;
    }
    if (segKind === "hard-break") {
      const endSegmentIndex = widths.length;
      pushMeasuredSegment(segText, 0, 0, 0, segKind, segStart, null, null, 0);
      chunks.push({
        startSegmentIndex: chunkStartSegmentIndex,
        endSegmentIndex,
        consumedEndSegmentIndex: widths.length
      });
      chunkStartSegmentIndex = widths.length;
      continue;
    }
    if (segKind === "tab") {
      pushMeasuredSegment(segText, 0, 0, 0, segKind, segStart, null, null, hasLetterSpacing ? countRenderedSpacingGraphemes(segText, segKind) : 0);
      continue;
    }
    if (segKind === "text" && isCJK2(segText)) {
      const measuredUnits = getCjkTextUnits(segText, engineProfile, wordBreak);
      for (let i = 0; i < measuredUnits.length; i++) {
        const unit = measuredUnits[i];
        const unitMetrics = getSegmentMetrics(unit.text, cache2);
        pushMeasuredTextSegment(unit.text, unitMetrics, "text", segStart + unit.start, unit.overflow === "grapheme" || analysis.isWordLike[mi] && (wordBreak === "keep-all" || unit.overflow === "word-like"));
      }
      continue;
    }
    pushMeasuredTextSegment(segText, getSegmentMetrics(segText, cache2), segKind, segStart, segKind === "text" && (analysis.isWordLike[mi] || isIndependentSymbolRun(segText)));
  }
  if (chunkStartSegmentIndex < widths.length) {
    chunks.push({
      startSegmentIndex: chunkStartSegmentIndex,
      endSegmentIndex: widths.length,
      consumedEndSegmentIndex: widths.length
    });
  }
  const segLevels = segStarts === null ? null : computeSegmentLevels(analysis.normalized, segStarts);
  if (segments !== null) {
    return {
      widths,
      lineEndFitAdvances,
      lineEndPaintAdvances,
      kinds,
      simpleLineWalkFastPath,
      segLevels,
      breakableFitAdvances,
      breakablePreferredBreaks,
      letterSpacing,
      spacingGraphemeCounts,
      discretionaryHyphenWidth,
      tabStopAdvance,
      chunks,
      segments
    };
  }
  return {
    widths,
    lineEndFitAdvances,
    lineEndPaintAdvances,
    kinds,
    simpleLineWalkFastPath,
    segLevels,
    breakableFitAdvances,
    breakablePreferredBreaks,
    letterSpacing,
    spacingGraphemeCounts,
    discretionaryHyphenWidth,
    tabStopAdvance,
    chunks
  };
}
function prepareInternal(text, font, includeSegments, options) {
  const wordBreak = options?.wordBreak ?? "normal";
  const letterSpacing = options?.letterSpacing ?? 0;
  const analysis = analyzeText(text, getEngineProfile(), options?.whiteSpace, wordBreak);
  return measureAnalysis(analysis, font, includeSegments, wordBreak, letterSpacing);
}
function prepareWithSegments(text, font, options) {
  return prepareInternal(text, font, true, options);
}
function getInternalPrepared(prepared) {
  return prepared;
}
function measureNaturalWidth(prepared) {
  let maxWidth = 0;
  walkPreparedLinesRaw(getInternalPrepared(prepared), Number.POSITIVE_INFINITY, (width) => {
    if (width > maxWidth)
      maxWidth = width;
  });
  return maxWidth;
}

// scripts/folia/node_modules/@chenglou/pretext/dist/rich-inline.js
var EMPTY_LAYOUT_CURSOR = { segmentIndex: 0, graphemeIndex: 0 };
var RICH_INLINE_START_CURSOR = {
  itemIndex: 0,
  segmentIndex: 0,
  graphemeIndex: 0
};
function getInternalPreparedRichInline(prepared) {
  return prepared;
}
function cloneCursor(cursor) {
  return {
    segmentIndex: cursor.segmentIndex,
    graphemeIndex: cursor.graphemeIndex
  };
}
function isLineStartCursor(cursor) {
  return cursor.segmentIndex === 0 && cursor.graphemeIndex === 0;
}
function isCollapsibleBoundaryWhitespace(code) {
  return code === 32 || code === 9 || code === 10 || code === 12 || code === 13;
}
function getCollapsedSpaceWidth(font, letterSpacing) {
  const { cache: cache2 } = getFontMeasurementState(font, false);
  return getSegmentMetrics(" ", cache2).width + letterSpacing;
}
function measureWholeItem(prepared) {
  const end = { segmentIndex: 0, graphemeIndex: 0 };
  return stepPreparedLineGeometry(prepared, end, Number.POSITIVE_INFINITY);
}
function endsInsideFirstSegment(segmentIndex, graphemeIndex) {
  return segmentIndex === 0 && graphemeIndex > 0;
}
function prepareRichInline(items) {
  const preparedItems = Array.from({ length: items.length });
  let pendingGapWidth = null;
  let breakAfterPreviousItem = false;
  for (let index = 0; index < items.length; index++) {
    const item = items[index];
    const letterSpacing = item.letterSpacing ?? 0;
    let start = 0;
    while (start < item.text.length && isCollapsibleBoundaryWhitespace(item.text.charCodeAt(start)))
      start++;
    if (start === item.text.length) {
      if (start > 0 && pendingGapWidth === null) {
        pendingGapWidth = getCollapsedSpaceWidth(item.font, letterSpacing);
      }
      continue;
    }
    let end = item.text.length;
    while (end > start && isCollapsibleBoundaryWhitespace(item.text.charCodeAt(end - 1)))
      end--;
    const hasLeadingWhitespace = start > 0;
    const hasTrailingWhitespace = end < item.text.length;
    const trimmedText = item.text.slice(start, end);
    const gapBefore = pendingGapWidth ?? (hasLeadingWhitespace ? getCollapsedSpaceWidth(item.font, letterSpacing) : 0);
    const prepared = prepareWithSegments(trimmedText, item.font, letterSpacing === 0 ? void 0 : { letterSpacing });
    const wholeWidth = measureWholeItem(prepared);
    const establishesLine = wholeWidth !== null || prepared.kinds.includes("zero-width-break");
    const preparedItem = {
      break: item.break ?? "normal",
      breakBefore: pendingGapWidth !== null || hasLeadingWhitespace || breakAfterPreviousItem,
      establishesLine,
      extraWidth: item.extraWidth ?? 0,
      gapBefore,
      naturalWidth: wholeWidth ?? 0,
      prepared
    };
    preparedItems[index] = preparedItem;
    if (establishesLine)
      breakAfterPreviousItem = prepared.kinds.at(-1) === "zero-width-break";
    pendingGapWidth = hasTrailingWhitespace ? getCollapsedSpaceWidth(item.font, letterSpacing) : null;
  }
  return {
    items: preparedItems
  };
}
function stepRichInlineLine(flow, maxWidth, cursor, collectFragment) {
  if (flow.items.length === 0 || cursor.itemIndex >= flow.items.length)
    return null;
  const safeWidth = Math.max(1, maxWidth);
  let hasContent = false;
  let lineWidth = 0;
  let remainingWidth = safeWidth;
  let itemIndex = cursor.itemIndex;
  lineLoop: while (itemIndex < flow.items.length) {
    const item = flow.items[itemIndex];
    if (item === void 0) {
      itemIndex++;
      cursor.segmentIndex = 0;
      cursor.graphemeIndex = 0;
      continue;
    }
    if (!isLineStartCursor(cursor) && cursor.segmentIndex === item.prepared.segments.length && cursor.graphemeIndex === 0) {
      itemIndex++;
      cursor.segmentIndex = 0;
      cursor.graphemeIndex = 0;
      continue;
    }
    if (!item.establishesLine) {
      collectFragment?.(itemIndex, 0, 0, cloneCursor(EMPTY_LAYOUT_CURSOR), {
        segmentIndex: item.prepared.segments.length,
        graphemeIndex: 0
      });
      itemIndex++;
      cursor.segmentIndex = 0;
      cursor.graphemeIndex = 0;
      continue;
    }
    const gapBefore = hasContent ? item.gapBefore : 0;
    const atItemStart = isLineStartCursor(cursor);
    if (item.break === "never") {
      if (!atItemStart) {
        itemIndex++;
        cursor.segmentIndex = 0;
        cursor.graphemeIndex = 0;
        continue;
      }
      const occupiedWidth = item.naturalWidth + item.extraWidth;
      const totalWidth = gapBefore + occupiedWidth;
      if (hasContent && totalWidth > remainingWidth)
        break lineLoop;
      collectFragment?.(itemIndex, gapBefore, occupiedWidth, cloneCursor(EMPTY_LAYOUT_CURSOR), {
        segmentIndex: item.prepared.segments.length,
        graphemeIndex: 0
      });
      hasContent = true;
      lineWidth += totalWidth;
      remainingWidth = safeWidth - lineWidth;
      itemIndex++;
      cursor.segmentIndex = 0;
      cursor.graphemeIndex = 0;
      continue;
    }
    const reservedWidth = gapBefore + item.extraWidth;
    if (hasContent && reservedWidth > remainingWidth)
      break lineLoop;
    if (atItemStart) {
      const totalWidth = reservedWidth + item.naturalWidth;
      if (totalWidth <= remainingWidth) {
        collectFragment?.(itemIndex, gapBefore, item.naturalWidth + item.extraWidth, cloneCursor(EMPTY_LAYOUT_CURSOR), {
          segmentIndex: item.prepared.segments.length,
          graphemeIndex: 0
        });
        hasContent = true;
        lineWidth += totalWidth;
        remainingWidth = safeWidth - lineWidth;
        itemIndex++;
        cursor.segmentIndex = 0;
        cursor.graphemeIndex = 0;
        continue;
      }
    }
    const availableWidth = Math.max(1, remainingWidth - reservedWidth);
    const lineEnd = {
      segmentIndex: cursor.segmentIndex,
      graphemeIndex: cursor.graphemeIndex
    };
    const lineWidthForItem = stepPreparedLineGeometry(item.prepared, lineEnd, availableWidth);
    if (lineWidthForItem === null) {
      itemIndex++;
      cursor.segmentIndex = 0;
      cursor.graphemeIndex = 0;
      continue;
    }
    if (cursor.segmentIndex === lineEnd.segmentIndex && cursor.graphemeIndex === lineEnd.graphemeIndex) {
      itemIndex++;
      cursor.segmentIndex = 0;
      cursor.graphemeIndex = 0;
      continue;
    }
    const itemOccupiedWidth = lineWidthForItem + item.extraWidth;
    const lineWidthContribution = gapBefore + itemOccupiedWidth;
    if (hasContent && atItemStart && lineWidthContribution > remainingWidth)
      break lineLoop;
    if (hasContent && atItemStart && item.breakBefore && endsInsideFirstSegment(lineEnd.segmentIndex, lineEnd.graphemeIndex)) {
      break lineLoop;
    }
    collectFragment?.(itemIndex, gapBefore, itemOccupiedWidth, cloneCursor(cursor), {
      segmentIndex: lineEnd.segmentIndex,
      graphemeIndex: lineEnd.graphemeIndex
    });
    hasContent = true;
    lineWidth += lineWidthContribution;
    remainingWidth = safeWidth - lineWidth;
    if (lineEnd.segmentIndex === item.prepared.segments.length && lineEnd.graphemeIndex === 0) {
      itemIndex++;
      cursor.segmentIndex = 0;
      cursor.graphemeIndex = 0;
      continue;
    }
    cursor.segmentIndex = lineEnd.segmentIndex;
    cursor.graphemeIndex = lineEnd.graphemeIndex;
    break;
  }
  if (!hasContent)
    return null;
  cursor.itemIndex = itemIndex;
  return lineWidth;
}
function layoutNextRichInlineLineRange(prepared, maxWidth, start = RICH_INLINE_START_CURSOR) {
  const flow = getInternalPreparedRichInline(prepared);
  const end = {
    itemIndex: start.itemIndex,
    segmentIndex: start.segmentIndex,
    graphemeIndex: start.graphemeIndex
  };
  const fragments = [];
  const width = stepRichInlineLine(flow, maxWidth, end, (itemIndex, gapBefore, occupiedWidth, fragmentStart, fragmentEnd) => {
    fragments.push({
      itemIndex,
      gapBefore,
      occupiedWidth,
      start: fragmentStart,
      end: fragmentEnd
    });
  });
  if (width === null)
    return null;
  return {
    fragments,
    width,
    end
  };
}
function walkRichInlineLineRanges(prepared, maxWidth, onLine) {
  let lineCount = 0;
  const cursor = { ...RICH_INLINE_START_CURSOR };
  while (true) {
    const line2 = layoutNextRichInlineLineRange(prepared, maxWidth, cursor);
    if (line2 === null)
      return lineCount;
    cursor.itemIndex = line2.end.itemIndex;
    cursor.segmentIndex = line2.end.segmentIndex;
    cursor.graphemeIndex = line2.end.graphemeIndex;
    onLine(line2);
    lineCount++;
  }
}
function measureRichInlineStats(prepared, maxWidth) {
  const flow = getInternalPreparedRichInline(prepared);
  let lineCount = 0;
  let maxLineWidth = 0;
  const cursor = {
    itemIndex: 0,
    segmentIndex: 0,
    graphemeIndex: 0
  };
  while (true) {
    const lineWidth = stepRichInlineLine(flow, maxWidth, cursor);
    if (lineWidth === null) {
      return {
        lineCount,
        maxLineWidth
      };
    }
    lineCount++;
    if (lineWidth > maxLineWidth)
      maxLineWidth = lineWidth;
  }
}

// folia:src/components/visualizer/lumiere/text/lineWrap.ts
var frameInsets = (width, height) => ({
  padX: Math.max(30, width * 0.065),
  padY: Math.max(30, height * 0.085)
});
var FRAME_CLEARANCE_X = 0.04;
var FRAME_CLEARANCE_TOP = 0.035;
var SUBTITLE_CLEARANCE = 0.2;
var frameBand = (width, height) => {
  const { padX, padY } = frameInsets(width, height);
  const left = padX / height + FRAME_CLEARANCE_X;
  return {
    left,
    right: width / height - left,
    top: padY / height + FRAME_CLEARANCE_TOP,
    bottom: Math.max(padY / height + FRAME_CLEARANCE_TOP + 0.2, 1 - SUBTITLE_CLEARANCE)
  };
};
var SINGLE_MIN_FIT = 0.8;
var MAX_LINES = 2;
var ROW_PITCH = 1.6;
var COLUMN_PITCH = 1.6;
var createTextMeasurer = (family2, weight, letterSpacing) => {
  const cache2 = /* @__PURE__ */ new Map();
  const font = (px) => glyphFont(weight, px, family2);
  const spacing = (px) => letterSpacing * px;
  return {
    font,
    spacing,
    natural: (text, px) => {
      const key = `${px}|${text}`;
      let width = cache2.get(key);
      if (width === void 0) {
        const ls = spacing(px);
        width = measureNaturalWidth(prepareWithSegments(text, font(px), ls === 0 ? void 0 : { letterSpacing: ls }));
        cache2.set(key, width);
      }
      return width;
    }
  };
};
var OPENING = /^[([{（【《「『〈〔［“‘]+$/u;
var spansOf = (glyphs, words) => {
  const isSpace = (index) => glyphs[index].char.trim().length === 0;
  const ranges = [];
  let cursor = 0;
  for (const word of words) {
    const start = Math.max(cursor, Math.min(glyphs.length, word.start));
    const end = Math.min(glyphs.length, word.end);
    for (let index = cursor; index < start; index += 1) ranges.push({ start: index, end: index + 1, word: false });
    if (end > start) ranges.push({ start, end, word: !word.blank });
    cursor = Math.max(cursor, end);
  }
  for (let index = cursor; index < glyphs.length; index += 1) ranges.push({ start: index, end: index + 1, word: false });
  const spans = [];
  for (const range of ranges) {
    let { start, end } = range;
    const lead = [];
    const tail = [];
    while (start < end && isSpace(start)) lead.push({ start, end: ++start, kind: "space" });
    while (end > start && isSpace(end - 1)) tail.unshift({ start: end - 1, end: end--, kind: "space" });
    spans.push(...lead);
    if (end > start) spans.push({ start, end, kind: range.word ? "word" : "punct" });
    spans.push(...tail);
  }
  return spans;
};
var textOf = (glyphs, start, end) => glyphs.slice(start, end).map((glyph) => glyph.char).join("");
var unitsOf = (glyphs, spans, heroPx) => {
  const pieces = [];
  const pxOf = (index) => heroPx * glyphs[index].scale;
  let pendingOpen = null;
  spans.forEach((span, index) => {
    if (span.kind === "space") {
      if (pendingOpen) pieces.push({ kind: "unit", unit: { start: pendingOpen.start, end: pendingOpen.end, text: textOf(glyphs, pendingOpen.start, pendingOpen.end), px: pxOf(pendingOpen.start) } });
      pendingOpen = null;
      pieces.push({ kind: "space", span });
      return;
    }
    const previous = pieces[pieces.length - 1];
    const next = spans[index + 1];
    if (span.kind === "punct") {
      const text = textOf(glyphs, span.start, span.end);
      if (OPENING.test(text) && next && next.kind !== "space") {
        pendingOpen = pendingOpen ? { ...pendingOpen, end: span.end } : span;
        return;
      }
      if (!pendingOpen && previous?.kind === "unit" && previous.unit.end === span.start) {
        previous.unit.end = span.end;
        return;
      }
    }
    const start = pendingOpen ? pendingOpen.start : span.start;
    pendingOpen = null;
    pieces.push({ kind: "unit", unit: { start, end: span.end, text: textOf(glyphs, span.start, span.end), px: pxOf(span.start) } });
  });
  const open = pendingOpen;
  if (open) pieces.push({ kind: "unit", unit: { start: open.start, end: open.end, text: textOf(glyphs, open.start, open.end), px: pxOf(open.start) } });
  return pieces;
};
var breakLines = (measurer, glyphs, pieces, advances, heroPx, lines) => {
  const extentOf = (unit) => advances.slice(unit.start, unit.end).reduce((sum, advance) => sum + advance, 0);
  const items = [];
  const unitOfItem = [];
  let widest = 0;
  let widestGap = 0;
  for (const piece of pieces) {
    if (piece.kind === "space") {
      const px = heroPx * glyphs[piece.span.start].scale;
      items.push({ text: textOf(glyphs, piece.span.start, piece.span.end), font: measurer.font(px), letterSpacing: measurer.spacing(px) });
      unitOfItem.push(null);
      widestGap = Math.max(widestGap, measurer.natural("a a", px) - measurer.natural("aa", px));
      continue;
    }
    const { unit } = piece;
    const extent = extentOf(unit);
    items.push({
      text: unit.text,
      font: measurer.font(unit.px),
      letterSpacing: measurer.spacing(unit.px),
      break: "never",
      extraWidth: extent - measurer.natural(unit.text, unit.px)
    });
    unitOfItem.push(unit);
    widest = Math.max(widest, extent);
  }
  const prepared = prepareRichInline(items);
  const walk = (maxWidth) => {
    const rows2 = [];
    walkRichInlineLineRanges(prepared, maxWidth, (line2) => {
      rows2.push(line2);
    });
    return rows2;
  };
  let rows = walk(Number.POSITIVE_INFINITY);
  if (lines > 1 && rows.length === 1 && rows[0].fragments.length > 1) {
    const total = rows[0].width;
    let target = (total + widest) / 2 + widestGap;
    if (measureRichInlineStats(prepared, target).lineCount > lines) target = total / 2 + widest + widestGap;
    rows = walk(target);
    if (rows.length > lines) {
      const kept = rows.slice(0, lines - 1);
      const rest = rows.slice(lines - 1);
      const fragments = rest.flatMap((row2, index) => row2.fragments.map((fragment2, k) => index > 0 && k === 0 ? { ...fragment2, gapBefore: widestGap } : fragment2));
      rows = [...kept, { fragments, width: fragments.reduce((sum, f) => sum + f.gapBefore + f.occupiedWidth, 0), end: rest[rest.length - 1].end }];
    }
  }
  const row = new Array(glyphs.length).fill(-1);
  const offset = new Array(glyphs.length).fill(0);
  const lengths = rows.map((line2) => line2.width);
  rows.forEach((line2, r) => {
    let cursor = 0;
    for (const fragment2 of line2.fragments) {
      const unit = unitOfItem[fragment2.itemIndex];
      const gapStart = cursor;
      cursor += fragment2.gapBefore;
      if (!unit) continue;
      for (let index = unit.start - 1; index >= 0 && row[index] === -1 && glyphs[index].char.trim().length === 0; index -= 1) {
        row[index] = r;
        offset[index] = gapStart + fragment2.gapBefore / 2;
      }
      const extent = extentOf(unit);
      const ratio = extent > 0 ? fragment2.occupiedWidth / extent : 0;
      let inner = cursor;
      for (let index = unit.start; index < unit.end; index += 1) {
        const advance = advances[index] * ratio;
        row[index] = r;
        offset[index] = inner + advance / 2;
        inner += advance;
      }
      cursor += fragment2.occupiedWidth;
    }
  });
  for (let index = 0; index < glyphs.length; index += 1) {
    if (row[index] !== -1) continue;
    const previous = index > 0 ? index - 1 : -1;
    if (previous >= 0 && row[previous] !== -1) {
      row[index] = row[previous];
      offset[index] = offset[previous] + advances[previous] / 2;
    }
  }
  for (let index = glyphs.length - 1; index >= 0; index -= 1) {
    if (row[index] !== -1) continue;
    row[index] = index + 1 < glyphs.length && row[index + 1] !== -1 ? row[index + 1] : 0;
    offset[index] = index + 1 < glyphs.length ? Math.max(0, offset[index + 1] - advances[index + 1] / 2) : 0;
  }
  return { row, offset, lengths: lengths.length ? lengths : [0] };
};
var splitLongUnits = (glyphs, pieces, advances, limit, heroPx) => pieces.flatMap((piece) => {
  if (piece.kind === "space") return [piece];
  const { unit } = piece;
  const extent = advances.slice(unit.start, unit.end).reduce((sum, advance) => sum + advance, 0);
  if (extent <= limit || unit.end - unit.start < 2) return [piece];
  const out = [];
  for (let index = unit.start; index < unit.end; index += 1) {
    const char = glyphs[index].char;
    const last = out[out.length - 1];
    if (last && last.kind === "unit" && !/[\p{L}\p{N}]/u.test(char)) {
      last.unit.end = index + 1;
      continue;
    }
    out.push({ kind: "unit", unit: { start: index, end: index + 1, text: char, px: heroPx * glyphs[index].scale } });
  }
  return out;
});
var flowLine = (measurer, glyphs, words, options) => {
  const { heroPx } = options;
  const spans = spansOf(glyphs, words);
  const basePieces = unitsOf(glyphs, spans, heroPx);
  const horizontal = new Array(glyphs.length).fill(0);
  for (const span of spans) {
    const px = heroPx * glyphs[span.start].scale;
    const text = textOf(glyphs, span.start, span.end);
    const width = measurer.natural(text, px);
    const canvas = glyphs.slice(span.start, span.end).reduce((sum, glyph) => sum + glyph.advance, 0);
    for (let index = span.start; index < span.end; index += 1) {
      horizontal[index] = canvas > 0 ? width * glyphs[index].advance / canvas : width / (span.end - span.start);
    }
  }
  const vertical = glyphs.map((glyph, index) => glyph.upright ? heroPx * glyph.scale * (1 + measurer.spacing(1)) : horizontal[index]);
  const variant = (orient, lines) => {
    const advances = orient === 0 ? horizontal : vertical;
    const pieces = splitLongUnits(glyphs, basePieces, advances, orient === 0 ? options.limits.horizontal : options.limits.vertical, heroPx);
    const { row, offset, lengths } = breakLines(measurer, glyphs, pieces, advances, heroPx, lines);
    const count = lengths.length;
    const along = Math.max(...lengths);
    const pitch = (orient === 0 ? ROW_PITCH : COLUMN_PITCH) * heroPx;
    const points = [];
    const spots = [];
    let inkX = 0;
    let inkY = 0;
    glyphs.forEach((glyph, index) => {
      const r = row[index];
      const size = heroPx * glyph.scale;
      let point;
      if (orient === 0) {
        const x = offset[index] - lengths[r] / 2;
        const rowY = (r - (count - 1) / 2) * pitch;
        point = { x, y: rowY + (1 - glyph.scale) * heroPx * 0.32 + glyph.jag };
        spots.push({ x, y: rowY });
        if (glyph.char.trim()) {
          inkX = Math.max(inkX, Math.abs(point.x) + advances[index] / 2);
          inkY = Math.max(inkY, Math.abs(point.y) + size / 2);
        }
      } else {
        const columnX = ((count - 1) / 2 - r) * pitch;
        const y = offset[index] - lengths[r] / 2;
        point = { x: columnX + glyph.jag * 0.8, y };
        spots.push({ x: columnX, y });
        if (glyph.char.trim()) {
          inkX = Math.max(inkX, Math.abs(point.x) + size / 2);
          inkY = Math.max(inkY, Math.abs(point.y) + advances[index] / 2);
        }
      }
      points.push(point);
    });
    return { points, spots, along, across: (count - 1) * pitch + heroPx, lines: count, inkWidth: inkX * 2, inkHeight: inkY * 2 };
  };
  return [
    [variant(0, 1), variant(0, MAX_LINES)],
    [variant(1, 1), variant(1, MAX_LINES)]
  ];
};
var fitScale = (along, budget, scale = 1) => Math.min(1, budget / Math.max(scale * along, 1e-6));
var shouldWrap = (flow, budget, scale) => flow[1].lines > 1 && scale * flow[0].along * SINGLE_MIN_FIT > budget;
var clampInto = (center, extent, lo, hi) => {
  if (extent >= hi - lo) return (lo + hi) / 2;
  return Math.min(hi - extent / 2, Math.max(lo + extent / 2, center));
};

// folia:src/components/visualizer/lumiere/text/windowLines.ts
var GLYPH_RANDOM_DRAWS = 19;
var LINE_RANDOM_DRAWS = 4;
var buildLineMetas = (lines) => {
  let offset = 0;
  return lines.map((line2) => {
    const graphemes = splitLyricGraphemes(line2.fullText);
    const meta = { line: line2, graphemes, randomOffset: offset, timing: void 0, keywordColors: void 0 };
    offset += graphemes.length * GLYPH_RANDOM_DRAWS + LINE_RANDOM_DRAWS;
    return meta;
  });
};
var lineTimingOf = (meta) => {
  if (!meta.timing) {
    const { line: line2, graphemes } = meta;
    const timings = buildGlyphTimings(line2);
    const sung = graphemes.flatMap((char, index) => char.trim().length === 0 ? [] : [timings[index] ?? { start: line2.startTime, end: line2.endTime }]);
    meta.timing = {
      timings,
      singStart: sung.length ? Math.min(...sung.map((timing) => timing.start)) : line2.startTime,
      singEnd: sung.length ? Math.max(...sung.map((timing) => timing.end)) : line2.endTime
    };
  }
  return meta.timing;
};
var keywordColorsOf = (meta, keywords) => {
  if (meta.keywordColors === void 0) {
    meta.keywordColors = keywords && keywords.length > 0 ? resolveGlyphKeywordColors(meta.line.fullText, keywords) : null;
  }
  return meta.keywordColors;
};
var buildLineView = (context, lineIndex, meta, rng) => {
  const { pixi, heroPx, sprites } = context;
  const { line: line2 } = meta;
  const { timings, singStart, singEnd } = lineTimingOf(meta);
  const layout = buildGlyphLine(pixi, {
    text: line2.fullText,
    fontPx: heroPx * MAX_WORD_SCALE,
    font: context.font,
    weight: context.weight,
    resolution: context.resolution,
    letterSpacing: context.spacing
  });
  const keywordColors = keywordColorsOf(meta, context.keywords);
  const words = segmentWords(line2);
  const wordSeed = `${context.seed}:${lineIndex}:${line2.fullText}`;
  const scales = wordScales(words, wordSeed);
  const jags = wordJags(words, scales, wordSeed);
  const wordOf = layout.glyphs.map((_, index) => Math.max(0, words.findIndex((word) => index >= word.start && index < word.end)));
  const glyphScale = (index) => scales[wordOf[index]] ?? 1;
  const glyphJag = (index) => (jags[wordOf[index]] ?? 0) * heroPx;
  const flow = flowLine(
    context.measurer,
    layout.glyphs.map((slice, index) => ({
      char: slice.char,
      scale: glyphScale(index),
      advance: slice.charWidth / MAX_WORD_SCALE * glyphScale(index),
      upright: slice.upright,
      jag: glyphJag(index)
    })),
    words,
    { heroPx, limits: context.limits }
  );
  const holder = new pixi.Container();
  const haloLayer = new pixi.Container();
  const starLayer = new pixi.Container();
  holder.label = `line-${lineIndex}`;
  const glyphs = layout.glyphs.map((slice, index) => {
    const glyph = new pixi.Sprite(slice.texture);
    glyph.anchor.set(slice.anchorX, slice.anchorY);
    holder.addChild(glyph);
    const a1 = rng() * Math.PI * 2;
    const a2 = a1 + Math.PI * (rng() < 0.5 ? 0.5 : 1.5) + (rng() - 0.5) * 0.8;
    const m1 = heroPx * (1.6 + rng() * 3.2);
    const m2 = heroPx * (1 + rng() * 2.6);
    const duration = 0.45 + rng() * 0.4;
    const flight = {
      c1: { x: Math.cos(a1) * m1, y: Math.sin(a1) * m1 },
      c2: { x: Math.cos(a2) * m2, y: Math.sin(a2) * m2 },
      delay: rng() * (1 - duration),
      duration,
      spin: (rng() - 0.5) * 2.4,
      wobble: rng() * Math.PI * 2
    };
    const halo = new pixi.Sprite(sprites.dot);
    halo.anchor.set(0.5);
    haloLayer.addChild(halo);
    const star = new pixi.Sprite(sprites.star);
    star.anchor.set(0.5);
    starLayer.addChild(star);
    if (slice.blank) {
      glyph.visible = false;
      halo.visible = false;
      star.visible = false;
    }
    const angle = -Math.PI / 2 + (rng() - 0.5) * 2.2;
    const scatterAngle = rng() * Math.PI * 2;
    const scatterDistance = 0.6 + rng() * 1.4;
    return {
      glyph,
      halo,
      star,
      timing: timings[index] ?? { start: line2.startTime, end: line2.endTime },
      blank: slice.blank,
      index,
      vRotation: slice.upright ? 0 : Math.PI / 2,
      flight,
      scale: glyphScale(index),
      starShape: {
        dx: -0.15 + rng() * 0.5,
        // 上下随机：多数落在字的上半，少数压到字脚下。
        dy: -0.62 + rng() ** 1.4 * 0.9,
        rotation: (rng() - 0.5) * 0.5,
        size: 0.65 + rng() * 0.7
      },
      drift: { dx: Math.cos(angle), dy: Math.sin(angle), speed: 0.6 + rng() * 0.9, spin: (rng() - 0.5) * 2 },
      scatter: { x: Math.cos(scatterAngle) * scatterDistance, y: Math.sin(scatterAngle) * scatterDistance },
      phase: rng() * Math.PI * 2,
      keyword: slice.blank ? null : keywordColors?.[index] ?? null,
      tints: null
    };
  });
  const spot = new pixi.Sprite(sprites.dot);
  spot.anchor.set(0.5);
  const [slow, fast] = context.driftSpeed;
  return {
    index: lineIndex,
    line: line2,
    layout,
    holder,
    haloLayer,
    starLayer,
    glyphs,
    keywordGlyphs: glyphs.filter((glyph) => glyph.keyword !== null),
    flow,
    // 落点用单独的随机流：排版换来换去时，别的随机量不受影响。
    placements: context.placementsOf(lineIndex),
    spot,
    singStart,
    singEnd,
    jitter: (rng() - 0.5) * 0.16,
    velocity: (() => {
      const angle = rng() * Math.PI * 2;
      const speed = slow + rng() * (fast - slow);
      return { x: Math.cos(angle) * speed, y: Math.sin(angle) * speed };
    })(),
    motionPhase: rng() * Math.PI * 2
  };
};

// folia:src/components/visualizer/lumiere/text/windowTiming.ts
var lumiereScaleMask12 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET12 = (1192 ^ lumiereScaleMask12) + Math.imul(349 ^ lumiereScaleMask12, 306 ^ lumiereScaleMask12) - ((1192 ^ lumiereScaleMask12) + Math.imul(349 ^ lumiereScaleMask12, 306 ^ lumiereScaleMask12));
var flightProgress = (flight, phase, lag = 0) => {
  const t = Math.min(1, Math.max(0, (phase - flight.delay - lag) / flight.duration));
  return t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2;
};
var flightPoint = (flight, from, to, s) => {
  const u = 1 - s;
  const a = u * u * u, b = 3 * u * u * s, c = 3 * u * s * s, d = s * s * s;
  return {
    x: a * from.x + b * (from.x + flight.c1.x) + c * (to.x + flight.c2.x) + d * to.x,
    y: a * from.y + b * (from.y + flight.c1.y) + c * (to.y + flight.c2.y) + d * to.y
  };
};
var TRACK_TIME = 0.45 + LUMIERE_NEUTRAL_OFFSET12;
var TRACK_SAMPLES = 20;
var LEAD = 1.2;
var SLIDE = 1.5;
var SLIDE_LAG = { [-2]: 0, [-1]: 0.15, 0: 0.3, 1: 0.5, 2: 0.6 };
var MAX_LAG = 0.6;
var DRIFT_SPEED = [0.013, 0.022];
var ORBIT = 0.03;
var LIGHT_UP = 0.3;
var SPOT_WINDOW = 0.3;
var SPOT_SAMPLES = 8;
var GATHER_LEAD = 1.6;
var GATHER = 1.8;
var smooth2 = (value) => {
  const t = Math.min(1, Math.max(0, value));
  return t * t * (3 - 2 * t);
};
var easeInOutCubic = (value) => {
  const t = Math.min(1, Math.max(0, value));
  return t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2;
};
var easeInOutSine = (value) => (1 - Math.cos(Math.PI * Math.min(1, Math.max(0, value)))) / 2;
var clamp016 = (value) => Math.min(1, Math.max(0, value));
var lerp = (a, b, k) => a + (b - a) * k;
var lerpPoint = (a, b, k) => ({ x: lerp(a.x, b.x, k), y: lerp(a.y, b.y, k) });
var resolveWindowCursor = (lines, time) => {
  let current = -1;
  for (let i = 0; i < lines.length; i += 1) {
    if (lines[i].startTime - LEAD <= time) current = i;
    else break;
  }
  const phase = current < 0 ? 1 : clamp016((time - (lines[current].startTime - LEAD)) / SLIDE);
  return { current, phase, slide: easeInOutSine(phase) };
};
var resolveLinePhase = (lines, current, relative, time) => {
  if (current < 0) return { phase: 1, start: Number.NEGATIVE_INFINITY };
  const start = lines[current].startTime - LEAD + (SLIDE_LAG[Math.max(-2, Math.min(2, relative))] ?? 0);
  return { phase: clamp016((time - start) / SLIDE), start };
};
var singingPosition = (glyphs, time) => {
  let position = 0;
  for (const glyph of glyphs) position += glyphProgress(glyph.timing, time);
  return position;
};
var positionToX = (glyphs, position) => {
  const n = glyphs.length;
  if (n === 0) return 0;
  const index = Math.min(n - 1, Math.max(0, position - 0.5));
  const lower = Math.floor(index);
  const upper = Math.min(n - 1, lower + 1);
  return glyphs[lower].center + (glyphs[upper].center - glyphs[lower].center) * (index - lower);
};
var resolveSpotX = (glyphs, time, window2 = SPOT_WINDOW) => {
  if (window2 <= 0) return positionToX(glyphs, singingPosition(glyphs, time));
  let x = 0;
  for (let s = 0; s < SPOT_SAMPLES; s += 1) {
    x += positionToX(glyphs, singingPosition(glyphs, time - window2 * s / (SPOT_SAMPLES - 1)));
  }
  return x / SPOT_SAMPLES;
};
var decayAmount = (decay, litAt, time) => {
  const age = time - litAt - decay.delay;
  return age > 0 ? decay.strength * 0.08 * age ** 1.5 : 0;
};
var DISSOLVE_FROM = 1;
var DISSOLVE_SPAN = 2;

// folia:src/components/visualizer/lumiere/text/windowSlots.ts
var freePlacements = (random, region, nextAlpha) => {
  const placement = (upper, alpha) => {
    const angle = upper ? Math.PI * (1.12 + random() * 0.76) : Math.PI * (0.12 + random() * 0.76);
    const rx = region.w * (0.24 + random() * 0.22);
    const ry = region.h * (0.3 + random() * 0.18);
    const vertical = random() < 0.5;
    return {
      dx: Math.cos(angle) * rx,
      dy: Math.sin(angle) * ry,
      scale: 0.5 + random() * 0.2,
      alpha,
      orient: vertical ? 1 : 0,
      rotation: (random() - 0.5) * (vertical ? 0.3 : 0.7),
      wrap: 0
    };
  };
  const farther = (slot) => ({ ...slot, dx: slot.dx * 1.45, dy: slot.dy * 1.45, scale: slot.scale * 0.85, alpha: 0 });
  const previous = placement(true, 0.9);
  const next = placement(false, nextAlpha);
  return /* @__PURE__ */ new Map([[-1, previous], [1, next], [-2, farther(previous)], [2, farther(next)]]);
};
var STACK_GAP = {
  vertical: { previous: 0.95, next: 0.88, farPrevious: 0.78, farNext: 0.7 },
  horizontal: { previous: 0.93, next: 0.735, farPrevious: 0.56, farNext: 0.56 }
};
var fixedSlot = (typography, relative, region, fontH, nextAlpha, across) => {
  const slot = (dx, dy, scale2, alpha2, orient2) => ({ dx, dy, scale: scale2, alpha: alpha2, orient: orient2, rotation: 0, wrap: 0 });
  const vertical = typography === "vertical";
  const orient = vertical ? 1 : 0;
  if (relative === 0) return slot(0, 0, 1, 1, orient);
  const previous = relative < 0;
  const far = Math.abs(relative) > 1;
  const nearScale = vertical ? 0.58 : 0.52;
  const scale = far ? vertical ? 0.48 : 0.44 : nearScale;
  const gap = STACK_GAP[vertical ? "vertical" : "horizontal"];
  const sign = previous ? -1 : 1;
  let offset = across(0, 1) / 2 + (previous ? gap.previous : gap.next) * fontH;
  if (far) offset += across(sign, nearScale) + (previous ? gap.farPrevious : gap.farNext) * fontH;
  offset += across(relative, scale) / 2;
  const alpha = previous ? far ? 0 : 0.9 : far ? 0 : nextAlpha;
  if (vertical) {
    return slot(-sign * offset, sign * (far ? 0.07 : 0.03), scale, alpha, orient);
  }
  return slot(sign * region.w * (far ? 0.24 : 0.16), sign * offset, scale, alpha, orient);
};
var CROSSED_CLEARANCE = 0.5;
var stackX = (kind) => kind === "vertical" ? 1 : 0;
var awayOf = (index, c, kind) => (index === c ? 0 : index < c ? -1 : 1) * (kind === "vertical" ? -1 : 1);
var sameSlot = (a, b) => a.dx === b.dx && a.dy === b.dy && a.scale === b.scale && a.alpha === b.alpha && a.orient === b.orient && a.rotation === b.rotation && a.wrap === b.wrap;

// folia:src/components/visualizer/lumiere/text/windowLineStore.ts
var PREBUILD = 2;
var KEEP_MARGIN = 2;
var createWindowLineStore = ({
  pixi,
  options,
  lineCount,
  measurer,
  limits,
  keywords: KEYWORDS,
  nextAlpha,
  glyphLayer,
  halos,
  stars,
  spots
}) => {
  const { region, heroPx, sprites } = options;
  const spacing = options.letterSpacing ?? 0;
  const metas = buildLineMetas(options.lines);
  const views = new Array(lineCount).fill(null);
  const built = [];
  const buildContext = {
    pixi,
    font: options.font,
    weight: options.weight,
    resolution: options.resolution,
    heroPx,
    spacing,
    seed: options.seed,
    sprites,
    measurer,
    limits,
    keywords: KEYWORDS,
    driftSpeed: DRIFT_SPEED,
    placementsOf: (lineIndex) => freePlacements(createRng(`${options.seed}:placements:${lineIndex}`), region, nextAlpha)
  };
  let tintedFor = null;
  const insertByLine = (parent, child, position) => {
    if (position >= parent.children.length) parent.addChild(child);
    else parent.addChildAt(child, position);
  };
  const buildLine = (index) => {
    const meta = metas[index];
    const lineView = buildLineView(buildContext, index, meta, createRngAt(`${options.seed}:window`, meta.randomOffset));
    let position = 0;
    while (position < built.length && built[position] < index) position += 1;
    built.splice(position, 0, index);
    insertByLine(glyphLayer, lineView.holder, position);
    insertByLine(halos, lineView.haloLayer, position);
    insertByLine(stars, lineView.starLayer, position);
    insertByLine(spots, lineView.spot, position);
    if (tintedFor) for (const glyph of lineView.keywordGlyphs) glyph.tints = keywordTints(tintedFor, glyph.keyword);
    views[index] = lineView;
    return lineView;
  };
  const releaseLine = (index) => {
    const lineView = views[index];
    if (!lineView) return;
    views[index] = null;
    built.splice(built.indexOf(index), 1);
    for (const item of [lineView.holder, lineView.haloLayer, lineView.starLayer, lineView.spot]) {
      item.parent?.removeChild(item);
      item.destroy({ children: true });
    }
    lineView.layout.destroy();
  };
  const lineOf = (index) => views[index] ?? buildLine(index);
  const refreshKeywordTints = (litColor) => {
    if (tintedFor && tintedFor[0] === litColor[0] && tintedFor[1] === litColor[1] && tintedFor[2] === litColor[2]) return;
    tintedFor = [litColor[0], litColor[1], litColor[2]];
    for (const index of built) {
      for (const glyph of views[index].keywordGlyphs) glyph.tints = keywordTints(litColor, glyph.keyword);
    }
  };
  const syncBuilt = (low, high) => {
    for (let k = built.length - 1; k >= 0; k -= 1) {
      const index = built[k];
      if (index >= low && index <= high) continue;
      if (index < low - KEEP_MARGIN || index > high + KEEP_MARGIN) {
        releaseLine(index);
        continue;
      }
      const lineView = views[index];
      lineView.holder.visible = false;
      lineView.haloLayer.visible = false;
      lineView.starLayer.visible = false;
      lineView.spot.visible = false;
    }
  };
  const prebuild = (high) => {
    for (let index = high + 1; index <= Math.min(lineCount - 1, high + PREBUILD); index += 1) {
      if (views[index]) continue;
      buildLine(index);
      const lineView = views[index];
      lineView.holder.visible = false;
      lineView.haloLayer.visible = false;
      lineView.starLayer.visible = false;
      lineView.spot.visible = false;
      return;
    }
  };
  return {
    metas,
    lineOf,
    /** 已构建的第 index 行（没建的是 null）。 */
    viewAt: (index) => views[index],
    refreshKeywordTints,
    syncBuilt,
    prebuild,
    /** 释放全部已构建的行。 */
    releaseAll: () => {
      for (let k = built.length - 1; k >= 0; k -= 1) releaseLine(built[k]);
    }
  };
};

// folia:src/components/visualizer/lumiere/text/lineClearance.ts
var AWAY_SOFTNESS = 5e-3;
var HOLD = 0.018;
var softAbs = (a) => Math.sqrt(a * a + AWAY_SOFTNESS * AWAY_SOFTNESS) - AWAY_SOFTNESS;
var awayDrift = (drift, away) => {
  if (away === 0) return drift;
  const sign = away > 0 ? 1 : -1;
  const along = drift * sign;
  return drift + Math.abs(away) * (softAbs(along) - along) * sign;
};
var heldDrift = (vx, vy, age, axis) => {
  const speed = Math.hypot(vx, vy);
  if (speed < 1e-9) return 0;
  const phi = speed * age / HOLD;
  const along = HOLD * Math.sin(phi);
  const turn = HOLD * (1 - Math.cos(phi));
  const ux = vx / speed;
  const uy = vy / speed;
  return axis === 0 ? along * ux - turn * uy : along * uy + turn * ux;
};
var PROTECT_FLOOR = 0.4;
var PROTECT_MARGIN = 0.5;
var createProtectBox = () => ({ line: -1, x: 0, y: 0, cos: 1, sin: 0, halfW: 0, halfH: 0, margin: 1, weight: 0 });
var smooth3 = (value) => {
  const t = Math.min(1, Math.max(0, value));
  return t * t * (3 - 2 * t);
};
var protectionAt = (boxes, count, line2, x, y, half) => {
  let protect = 0;
  for (let i = 0; i < count; i += 1) {
    const box = boxes[i];
    if (box.line === line2 || box.weight <= 0) continue;
    const dx = x - box.x;
    const dy = y - box.y;
    const u = Math.abs(dx * box.cos + dy * box.sin) - box.halfW - half;
    const v = Math.abs(dy * box.cos - dx * box.sin) - box.halfH - half;
    const outside = u > 0 && v > 0 ? Math.hypot(u, v) : Math.max(u, v, 0);
    protect += box.weight * (1 - smooth3(outside / box.margin));
  }
  return Math.min(1, protect);
};
var protectedAlpha = (protect) => 1 - (1 - PROTECT_FLOOR) * protect;

// folia:src/components/visualizer/lumiere/text/windowGeometry.ts
var WINDOW_REACH = 3;
var toWorld = (transform, point) => {
  const cos = Math.cos(transform.rotation);
  const sin = Math.sin(transform.rotation);
  return {
    x: transform.x + (point.x * cos - point.y * sin) * transform.scale,
    y: transform.y + (point.x * sin + point.y * cos) * transform.scale
  };
};
var createWindowGeometry = ({
  options,
  lineCount,
  band: band2,
  columnCap,
  maxWidthOf,
  nextAlpha,
  lineOf
}) => {
  const { height, region, heroPx, typography, decay } = options;
  const fontH = heroPx / height;
  const driftScale = options.drift ?? 1;
  const typographyAt = (c) => options.typographyOf ? options.typographyOf(Math.max(0, Math.min(lineCount - 1, c))) : typography;
  const settle = (index, kind, orient, scale) => {
    const flow = lineOf(index).flow[orient];
    const budget = orient === 1 ? columnCap : maxWidthOf(kind);
    const wrap3 = shouldWrap(flow, budget, scale) ? 1 : 0;
    const variant = flow[wrap3];
    return { wrap: wrap3, variant, scale: scale * fitScale(variant.along, budget, scale) };
  };
  const acrossOf = (index, kind, orient, scale) => {
    if (index < 0 || index >= lineCount) return fontH * scale;
    const settled = settle(index, kind, orient, scale);
    return settled.variant.across / height * settled.scale;
  };
  const windowShift = (current, kind) => {
    if (current < 0 || current >= lineCount) return { x: 0, y: 0 };
    const orient = kind === "vertical" ? 1 : 0;
    const { variant, scale } = settle(current, kind, orient, 1);
    const w = variant.inkWidth / height * scale;
    const h = variant.inkHeight / height * scale;
    return {
      x: clampInto(region.cx, w, band2.left, band2.right) - region.cx,
      y: clampInto(region.cy, h, band2.top, band2.bottom) - region.cy
    };
  };
  const slotCache = /* @__PURE__ */ new Map();
  const slotOf = (index, current, kind) => {
    const key = `${index}|${current}|${kind}`;
    const cached = slotCache.get(key);
    if (cached) return cached;
    const view = lineOf(index);
    const clamped = Math.max(-2, Math.min(2, index - current));
    const shift = windowShift(current, kind);
    let slot;
    let wrap3 = null;
    if (kind === "crossed" && clamped !== 0) {
      const base = view.placements.get(clamped);
      const baseOrient = base.orient >= 0.5 ? 1 : 0;
      const sign = base.dy < 0 ? -1 : 1;
      const currentHalf = current >= 0 && current < lineCount ? (() => {
        const settled = settle(current, kind, 0, 1);
        return settled.variant.inkHeight / height * settled.scale / 2;
      })() : fontH / 2;
      const gap = fontH * CROSSED_CLEARANCE;
      const centerY = region.cy + shift.y;
      const room = sign < 0 ? centerY - currentHalf - gap - band2.top : band2.bottom - (centerY + currentHalf + gap);
      const flow = view.flow[baseOrient];
      const budget = baseOrient === 1 ? columnCap : maxWidthOf(kind);
      const tilt = Math.abs(base.rotation) + 0.03;
      const heightOf = (w2, s) => (flow[w2].inkHeight * Math.cos(tilt) + flow[w2].inkWidth * Math.sin(tilt)) / height * s * fitScale(flow[w2].along, budget, s);
      let scale = base.scale;
      let w = settle(index, kind, baseOrient, scale).wrap ? 1 : 0;
      if (baseOrient === 1 && room > 0) {
        if (w === 0 && flow[1].lines > 1 && heightOf(0, scale) > room) w = 1;
        const tall = heightOf(w, scale);
        if (tall > room) scale = Math.max(base.scale * 0.5, scale * (room / tall));
      }
      wrap3 = w;
      const clearance = currentHalf + gap + heightOf(w, scale) / 2;
      const dy = sign * Math.max(Math.abs(base.dy), clearance);
      const wider = baseOrient === 1 ? Math.max(0, acrossOf(index, kind, 1, scale) - fontH * scale) / 2 : 0;
      slot = { ...base, scale, dy, dx: base.dx + Math.sign(base.dx) * wider };
    } else {
      const orient = kind === "vertical" ? 1 : 0;
      slot = fixedSlot(kind === "crossed" ? "horizontal" : kind, clamped, region, fontH, nextAlpha, (offset, scale) => acrossOf(offset === clamped ? index : current + offset, kind, orient, scale));
    }
    const result = {
      ...slot,
      dx: slot.dx + shift.x,
      dy: slot.dy + shift.y,
      wrap: wrap3 ?? settle(index, kind, slot.orient >= 0.5 ? 1 : 0, slot.scale).wrap
    };
    slotCache.set(key, result);
    return result;
  };
  const firstLiveChange = (time, current) => {
    let c = current;
    while (c >= 0 && options.lines[c].startTime - LEAD + MAX_LAG + SLIDE + TRACK_TIME > time) c -= 1;
    return c + 1;
  };
  const lineTransform = (index, time) => {
    const view = lineOf(index);
    const { current } = resolveWindowCursor(options.lines, time);
    const first = firstLiveChange(time, current);
    const base = first - 1;
    const initialKind = typographyAt(base);
    const initial = slotOf(index, base, initialKind);
    let dx = initial.dx, dy = initial.dy, scale = initial.scale, rotation = initial.rotation;
    let alpha = initial.alpha, orient = initial.orient, wrap3 = initial.wrap;
    let latest = null;
    let restOrient = initial.orient;
    let restWrap = initial.wrap;
    const moves = [];
    let widthCap = maxWidthOf(initialKind);
    let jitterOn = initialKind === "crossed" ? 0 : 1;
    let awayX = stackX(initialKind) * awayOf(index, base, initialKind);
    let awayY = (1 - stackX(initialKind)) * awayOf(index, base, initialKind);
    let hero = index === base ? 1 : 0;
    const last = Math.min(lineCount - 1, current);
    for (let c = first; c <= last; c += 1) {
      const beforeKind = typographyAt(c - 1);
      const afterKind = typographyAt(c);
      const before = slotOf(index, c - 1, beforeKind);
      const after = slotOf(index, c, afterKind);
      const kindChanged = beforeKind !== afterKind;
      if (sameSlot(before, after) && !kindChanged) continue;
      const { phase, start } = resolveLinePhase(options.lines, c, index - c, time);
      const k = easeInOutSine(phase);
      if (kindChanged) {
        widthCap += (maxWidthOf(afterKind) - maxWidthOf(beforeKind)) * k;
        jitterOn += ((afterKind === "crossed" ? 0 : 1) - (beforeKind === "crossed" ? 0 : 1)) * k;
      }
      const awayBefore = awayOf(index, c - 1, beforeKind);
      const awayAfter = awayOf(index, c, afterKind);
      awayX += (stackX(afterKind) * awayAfter - stackX(beforeKind) * awayBefore) * k;
      awayY += ((1 - stackX(afterKind)) * awayAfter - (1 - stackX(beforeKind)) * awayBefore) * k;
      hero += ((index === c ? 1 : 0) - (index === c - 1 ? 1 : 0)) * k;
      const fade = after.alpha < before.alpha ? easeInOutCubic(phase / 0.6) : after.alpha > before.alpha ? easeInOutCubic((phase - 0.4) / 0.6) : k;
      dx += (after.dx - before.dx) * k;
      dy += (after.dy - before.dy) * k;
      scale += (after.scale - before.scale) * k;
      rotation += (after.rotation - before.rotation) * k;
      alpha += (after.alpha - before.alpha) * fade;
      orient += (after.orient - before.orient) * phase;
      wrap3 += (after.wrap - before.wrap) * k;
      if (phase > 0) latest = { before, after, phase, start, kind: afterKind };
      if (phase >= 1) {
        restOrient = after.orient;
        restWrap = after.wrap;
        moves.length = 0;
      } else if (phase > 0) {
        moves.push({
          toOrient: after.orient,
          toWrap: after.wrap,
          phase,
          fly: options.alwaysFly === true || afterKind === "crossed" || before.orient !== after.orient
        });
      }
    }
    const o = clamp016(orient);
    const w = clamp016(wrap3);
    const [hSingle, hWrapped] = view.flow[0];
    const [vSingle, vWrapped] = view.flow[1];
    const fitH = lerp(fitScale(hSingle.along, widthCap, scale), fitScale(hWrapped.along, widthCap, scale), w);
    const fitV = lerp(fitScale(vSingle.along, columnCap, scale), fitScale(vWrapped.along, columnCap, scale), w);
    const fitted = scale * lerp(fitH, fitV, o);
    const jitter = jitterOn * view.jitter * region.w * clamp016((1 - scale) / 0.5);
    const baseX = region.cx + dx + jitter * (1 - orient);
    const baseY = region.cy + dy + jitter * 0.5 * orient;
    const alongH = lerp(hSingle.inkWidth, hWrapped.inkWidth, w) / height * fitted;
    const alongV = lerp(vSingle.inkHeight, vWrapped.inkHeight, w) / height * fitted;
    const x = baseX + (clampInto(baseX, alongH, band2.left, band2.right) - baseX) * (1 - o) * jitterOn;
    const y = baseY + (clampInto(baseY, alongV, band2.top, band2.bottom) - baseY) * o * jitterOn;
    const age = time - view.line.startTime;
    const m = view.motionPhase;
    const { x: vx, y: vy } = view.velocity;
    const orbitX = Math.sin(time * 0.52 + m) * ORBIT;
    const orbitY = Math.cos(time * 0.41 + m * 1.3) * ORBIT * 0.7;
    const held = clamp016(hero);
    const driftX = lerp(awayDrift((vx * age + orbitX) * driftScale, awayX), (heldDrift(vx, vy, age, 0) + orbitX) * driftScale, held);
    const driftY = lerp(awayDrift((vy * age + orbitY) * driftScale, awayY), (heldDrift(vx, vy, age, 1) + orbitY) * driftScale, held);
    const settledOrient = latest ? latest.after.orient : initial.orient;
    const settledWrap = latest ? latest.after.wrap : initial.wrap;
    return {
      current,
      x: (x + driftX) * height,
      y: (y + driftY) * height,
      scale: fitted * (1 + 0.025 * Math.sin(time * 0.43 + m)),
      rotation: rotation + 0.03 * Math.sin(time * 0.23 + m * 0.7),
      alpha: clamp016(alpha),
      fromOrient: latest ? latest.before.orient : settledOrient,
      toOrient: settledOrient,
      fromWrap: latest ? latest.before.wrap : settledWrap,
      toWrap: settledWrap,
      wrap: w,
      orient: o,
      phase: latest ? latest.phase : 1,
      // 纵横交错时每次换槽位都飞；另两种排版只在朝向变化时飞。
      fly: latest !== null && latest.phase < 1 && (options.alwaysFly === true || latest.kind === "crossed" || latest.before.orient !== latest.after.orient),
      slideStart: latest ? latest.start : Number.NEGATIVE_INFINITY,
      restOrient,
      restWrap,
      moves
    };
  };
  const glyphLocal = (view, glyph, time, transform) => {
    const at = (orient, wrap3) => view.flow[orient >= 0.5 ? 1 : 0][wrap3 >= 0.5 ? 1 : 0].points[glyph.index];
    let point = at(transform.restOrient, transform.restWrap);
    let orientation = transform.restOrient;
    let flying = 0;
    for (const move of transform.moves) {
      const target = at(move.toOrient, move.toWrap);
      if (move.fly) {
        const s = flightProgress(glyph.flight, move.phase);
        point = flightPoint(glyph.flight, point, target, s);
        orientation = lerp(orientation, move.toOrient, s);
        flying = Math.max(flying, Math.sin(Math.PI * s));
      } else {
        const k = easeInOutSine(move.phase);
        point = lerpPoint(point, target, k);
        orientation = lerp(orientation, move.toOrient, k);
      }
    }
    let x = point.x;
    let y = point.y;
    let rotation = glyph.vRotation * orientation + glyph.flight.spin * flying;
    const pulse = 1 - 0.28 * flying;
    const gather = Math.min(
      smooth2((time - (view.line.startTime - LEAD - GATHER_LEAD)) / GATHER),
      smooth2((options.tfnArrivalElapsed?.() ?? Infinity) / GATHER)
    );
    const scatter = (1 - gather) ** 2 * decay.strength;
    x += glyph.scatter.x * heroPx * scatter;
    y += glyph.scatter.y * heroPx * scatter;
    const amount = decayAmount(decay, glyph.timing.start, time) * glyph.drift.speed;
    x += glyph.drift.dx * heroPx * amount;
    y += glyph.drift.dy * heroPx * amount;
    rotation += glyph.drift.spin * amount * 0.18;
    const breath = heroPx * 0.022 * Math.min(1, decay.strength + 0.3);
    x += Math.sin(time * 0.9 + glyph.phase) * breath;
    y += Math.cos(time * 1.13 + glyph.phase * 1.7) * breath;
    return { x, y, rotation, gather, flying, scale: glyph.scale * pulse };
  };
  const activeRange = (time) => {
    const { current } = resolveWindowCursor(options.lines, time);
    const first = firstLiveChange(time, current);
    return {
      current,
      low: Math.max(0, Math.min(current, first) - WINDOW_REACH),
      high: Math.min(lineCount - 1, Math.max(current, 0) + WINDOW_REACH)
    };
  };
  return { fontH, lineTransform, glyphLocal, activeRange };
};

// folia:src/components/visualizer/lumiere/text/windowProtection.ts
var createWindowProtection = ({ lines, heroPx, lineOf }) => {
  const protectBoxes = [createProtectBox(), createProtectBox(), createProtectBox(), createProtectBox()];
  let protectCount = 0;
  const buildProtectBoxes = (time, current, low, frameTransforms) => {
    protectCount = 0;
    let later = 0;
    for (let j = current; j >= low && protectCount < protectBoxes.length; j -= 1) {
      const eased = easeInOutSine((time - (lines[j].startTime - LEAD)) / SLIDE);
      const transform = frameTransforms[j];
      const o = clamp016(transform.orient);
      const weight = (eased - later) * clamp016(transform.alpha) * (1 - 4 * o * (1 - o));
      later = eased;
      if (weight > 1e-4) {
        const [hSingle, hWrapped] = lineOf(j).flow[0];
        const [vSingle, vWrapped] = lineOf(j).flow[1];
        const w = transform.wrap;
        const inkW = lerp(lerp(hSingle.inkWidth, hWrapped.inkWidth, w), lerp(vSingle.inkWidth, vWrapped.inkWidth, w), transform.orient);
        const inkH = lerp(lerp(hSingle.inkHeight, hWrapped.inkHeight, w), lerp(vSingle.inkHeight, vWrapped.inkHeight, w), transform.orient);
        const box = protectBoxes[protectCount];
        box.line = j;
        box.x = transform.x;
        box.y = transform.y;
        box.cos = Math.cos(transform.rotation);
        box.sin = Math.sin(transform.rotation);
        box.halfW = inkW / 2 * transform.scale;
        box.halfH = inkH / 2 * transform.scale;
        box.margin = PROTECT_MARGIN * heroPx * transform.scale;
        box.weight = weight;
        protectCount += 1;
      }
      if (eased >= 1) break;
    }
  };
  return {
    build: buildProtectBoxes,
    /** 第 index 行一个字（画面坐标、半径）的保护系数：落进别的行的保护框就压暗，飞行途中按飞行强度不压。 */
    shield: (index, x, y, radius, flying) => protectCount > 0 ? protectedAlpha(protectionAt(protectBoxes, protectCount, index, x, y, radius) * (1 - flying)) : 1
  };
};

// folia:src/components/visualizer/lumiere/text/lyricWindow.ts
var createLyricWindow = (pixi, options) => {
  const { height, heroPx, decay } = options;
  const view = new pixi.Container();
  const trackLayer = new pixi.Graphics();
  const halos = new pixi.Container();
  const glyphLayer = new pixi.Container();
  const stars = new pixi.Container();
  const spots = new pixi.Container();
  const trackHolder = new pixi.Container({ isRenderGroup: true });
  trackHolder.addChild(trackLayer);
  view.addChild(spots, trackHolder, halos, glyphLayer, stars);
  const lineCount = options.lines.length;
  const nextAlpha = options.neighbors >= 2 ? 0.95 : 0;
  const band2 = frameBand(options.width, height);
  const columnCap = (band2.bottom - band2.top) * height;
  const maxWidthOf = (kind) => (band2.right - band2.left) * height * (kind === "crossed" ? 0.9 : 1);
  const measurer = createTextMeasurer(options.font, options.weight, options.letterSpacing ?? 0);
  const KEYWORDS = options.keywords && options.keywords.length > 0 ? options.keywords : void 0;
  const lines = createWindowLineStore({
    pixi,
    options,
    lineCount,
    measurer,
    limits: { horizontal: maxWidthOf("horizontal"), vertical: columnCap },
    keywords: KEYWORDS,
    nextAlpha,
    glyphLayer,
    halos,
    stars,
    spots
  });
  const { metas, lineOf } = lines;
  const geometry = createWindowGeometry({ options, lineCount, band: band2, columnCap, maxWidthOf, nextAlpha, lineOf });
  const { lineTransform, glyphLocal, activeRange } = geometry;
  const protection = createWindowProtection({ lines: options.lines, heroPx, lineOf });
  const frameTransforms = new Array(lineCount);
  let tracksDrawn = false;
  const drawTracks = (index, view2, time, transform, alpha, color) => {
    if (alpha <= 3e-3 || !Number.isFinite(transform.slideStart)) return;
    if (time > transform.slideStart + SLIDE + TRACK_TIME) return;
    const from = Math.max(transform.slideStart, time - TRACK_TIME);
    if (time - from < 1e-3) return;
    const samples = Array.from({ length: TRACK_SAMPLES + 1 }, (_, i) => from + (time - from) * i / TRACK_SAMPLES);
    const transforms = samples.map((sample) => lineTransform(index, sample));
    if (!transforms.some((sample) => sample.fly)) return;
    const width = 1.2;
    tracksDrawn = true;
    view2.glyphs.forEach((glyph) => {
      if (glyph.blank) return;
      let length = 0;
      let previous = null;
      let fontPx = heroPx;
      let flying = 0;
      samples.forEach((sample, i) => {
        const local = glyphLocal(view2, glyph, sample, transforms[i]);
        const world = toWorld(transforms[i], local);
        fontPx = heroPx * transforms[i].scale * local.scale;
        flying = local.flying;
        const wobble = Math.sin(i * 0.9 + glyph.flight.wobble + sample * 6) * heroPx * 0.02;
        const x = world.x + wobble;
        const y = world.y - wobble * 0.6;
        if (previous) {
          length += Math.hypot(x - previous.x, y - previous.y);
          trackLayer.lineTo(x, y);
        } else {
          trackLayer.moveTo(x, y);
        }
        previous = { x, y };
      });
      const strength = Math.min(1, length / (heroPx * 3));
      const head = previous;
      const shield = head ? protection.shield(index, head.x, head.y, fontPx / 2, flying) : 1;
      if (strength > 0.05) trackLayer.stroke({ width, color, alpha: alpha * 0.55 * strength * shield, cap: "round", join: "round" });
      else trackLayer.beginPath();
    });
  };
  const update = (frame2) => {
    const { time, beams, litColor, unlitColor, unlitAlpha, intensity } = frame2;
    trackLayer.visible = frame2.hideTrails !== true;
    if (tracksDrawn) {
      trackLayer.clear();
      tracksDrawn = false;
    }
    if (KEYWORDS) lines.refreshKeywordTints(litColor);
    const litHex = hexOf(litColor);
    const starHex = hexOf(mixRgb(litColor, WHITE, 0.5));
    const { low, high, current: cursor } = activeRange(time);
    lines.syncBuilt(low, high);
    for (let index = low; index <= high; index += 1) frameTransforms[index] = lineTransform(index, time);
    protection.build(time, cursor, low, frameTransforms);
    for (let index = low; index <= high; index += 1) {
      const view2 = lines.viewAt(index);
      const transform = frameTransforms[index];
      const { current, scale } = transform;
      const lineAlpha = transform.alpha * intensity;
      const visible = lineAlpha > 3e-3;
      view2.holder.visible = visible;
      view2.haloLayer.visible = visible;
      view2.starLayer.visible = visible;
      view2.holder.position.set(transform.x, transform.y);
      view2.holder.scale.set(scale);
      view2.holder.rotation = transform.rotation;
      const passed = index < current || index === current && time > view2.line.endTime;
      const passedAge = passed ? time - view2.line.endTime : 0;
      const passedDim = passed ? lerp(1, 0.75, clamp016(passedAge / 2.5)) : 1;
      const lineFontPx = heroPx * scale;
      if (trackLayer.visible) drawTracks(index, view2, time, transform, lineAlpha * passedDim, litHex);
      for (const glyph of view2.glyphs) {
        if (glyph.blank) continue;
        if (!visible) {
          glyph.glyph.visible = false;
          glyph.halo.visible = false;
          glyph.star.visible = false;
          continue;
        }
        const local = glyphLocal(view2, glyph, time, transform);
        glyph.glyph.position.set(local.x, local.y);
        glyph.glyph.rotation = local.rotation;
        glyph.glyph.scale.set(local.scale / MAX_WORD_SCALE);
        const fontPx = lineFontPx * local.scale;
        const { x: gx, y: gy } = toWorld(transform, local);
        const lit = smooth2((time - glyph.timing.start) / Math.max(glyph.timing.end - glyph.timing.start, LIGHT_UP));
        const flash = flashEnvelope(glyph.timing, time, 0.45);
        const illumination = compressLight(lightAt(beams, gx / height, gy / height));
        const heat = clamp016(illumination * 1.3 + flash * 0.2);
        const dissolve = 1 - clamp016((decayAmount(decay, glyph.timing.start, time) * glyph.drift.speed - DISSOLVE_FROM) / DISSOLVE_SPAN);
        const shield = protection.shield(index, gx, gy, fontPx / 2, local.flying);
        const glyphAlpha = lineAlpha * passedDim * dissolve * (0.35 + 0.65 * local.gather) * shield;
        glyph.glyph.visible = true;
        const revealed = Math.min(1, unlitAlpha + illumination * 0.45 + local.flying * 0.4);
        glyph.glyph.alpha = glyphAlpha * (revealed * (1 - lit) + lit * Math.min(1, 0.55 + 0.4 * heat + 0.3 * local.flying));
        const tints = glyph.tints;
        const hot = mixRgb(tints ? tints.glyph : litColor, WHITE, clamp016(0.08 * illumination + 0.1 * flash + 0.25 * local.flying));
        const cold = mixRgb(unlitColor, litColor, illumination * 0.35);
        glyph.glyph.tint = hexOf(mixRgb(cold, hot, lit));
        const haloAlpha = glyphAlpha * lit * (0.03 + 0.14 * illumination + 0.08 * flash) * (tints ? KEYWORD_HALO_GAIN : 1);
        glyph.halo.visible = true;
        if (haloAlpha > 3e-3) {
          glyph.halo.position.set(gx, gy);
          const size = fontPx * (2.2 + 0.8 * illumination);
          glyph.halo.width = size;
          glyph.halo.height = size * 0.9;
          glyph.halo.alpha = haloAlpha;
          glyph.halo.tint = tints ? tints.halo : litHex;
        } else {
          glyph.halo.scale.set(0);
        }
        const starAlpha = lineAlpha * flash * 0.55 * shield;
        glyph.star.visible = true;
        if (starAlpha > 3e-3) {
          const star = glyph.starShape;
          glyph.star.position.set(gx + fontPx * star.dx, gy + fontPx * star.dy);
          glyph.star.rotation = star.rotation * (1 + (1 - flash) * 0.6);
          const size = fontPx * star.size * (0.8 + 0.5 * flash);
          glyph.star.width = size;
          glyph.star.height = size;
          glyph.star.alpha = starAlpha;
          glyph.star.tint = tints ? tints.star : starHex;
        } else {
          glyph.star.scale.set(0);
        }
      }
      const spotAlpha = visible ? lineAlpha * smooth2((time - view2.singStart + 0.3) / 0.3) * (1 - smooth2((time - view2.singEnd) / 0.6)) : 0;
      view2.spot.visible = spotAlpha > 3e-3;
      if (view2.spot.visible) {
        const vertical = transform.toOrient >= 0.5;
        const spotOf = (wrap3) => {
          const path2 = view2.flow[vertical ? 1 : 0][wrap3].spots;
          return {
            x: resolveSpotX(view2.glyphs.map((glyph) => ({ timing: glyph.timing, center: path2[glyph.index].x })), time),
            y: resolveSpotX(view2.glyphs.map((glyph) => ({ timing: glyph.timing, center: path2[glyph.index].y })), time)
          };
        };
        const local = transform.wrap <= 0 ? spotOf(0) : transform.wrap >= 1 ? spotOf(1) : lerpPoint(spotOf(0), spotOf(1), transform.wrap);
        const position = toWorld(transform, local);
        const size = lineFontPx * 5;
        view2.spot.position.set(position.x, position.y);
        view2.spot.rotation = transform.rotation;
        view2.spot.width = size * (vertical ? 1 : 1.6);
        view2.spot.height = size * (vertical ? 1.6 : 1);
        view2.spot.alpha = 0.07 * spotAlpha;
        view2.spot.tint = litHex;
      }
    }
    lines.prebuild(high);
  };
  return {
    view,
    update,
    glyphTimes: (lineIndex) => {
      const meta = metas[lineIndex];
      if (!meta) return [];
      return meta.graphemes.flatMap((char, glyphIndex) => char.trim().length === 0 ? [] : [{ glyphIndex, start: (lineTimingOf(meta).timings[glyphIndex] ?? { start: meta.line.startTime }).start }]);
    },
    glyphAnchor: (lineIndex, glyphIndex, time) => {
      const transform = lineTransform(lineIndex, time);
      const view2 = lineOf(lineIndex);
      const local = glyphLocal(view2, view2.glyphs[glyphIndex], time, transform);
      const world = toWorld(transform, local);
      return { x: world.x, y: world.y, fontPx: heroPx * transform.scale * local.scale };
    },
    lineAnchor: (lineIndex, time) => {
      const transform = lineTransform(lineIndex, time);
      return { x: transform.x, y: transform.y, scale: transform.scale, alpha: transform.alpha };
    },
    glyphKeyword: (lineIndex, glyphIndex) => {
      const meta = metas[lineIndex];
      if (!meta || (meta.graphemes[glyphIndex] ?? "").trim().length === 0) return null;
      return keywordColorsOf(meta, KEYWORDS)?.[glyphIndex] ?? null;
    },
    destroy: () => {
      lines.releaseAll();
      view.destroy({ children: true, context: true });
    }
  };
};

// folia:src/components/visualizer/lumiere/lumiereUnitLayout.ts
var resolveLumiereLeadShot = (shots) => shots[Math.max(0, shots.findIndex((shot) => shot.lines.length > 0))];
var lumiereTypographyOfLine = (shots) => (lineIndex) => {
  let found = shots[0];
  for (const shot of shots) {
    if (shot.lines.includes(lineIndex)) return shot.profile.typography;
    if (shot.lines.length > 0 && shot.lines[0] < lineIndex) found = shot;
  }
  return found.profile.typography;
};
var resolveLumiereCameraProgress = (time, span, sections) => {
  const eased = (start, end) => {
    const linear2 = Math.min(1, Math.max(0, (time - start) / Math.max(end - start, 1e-3)));
    return (1 - Math.cos(linear2 * Math.PI)) / 2;
  };
  if (!sections || sections.length === 0) return eased(span.startTime, span.endTime);
  let index = 0;
  for (let i = 0; i < sections.length; i += 1) if (sections[i].startTime <= time) index = i;
  const section = sections[index];
  const progress = eased(section.startTime, section.endTime);
  return index % 2 === 0 ? progress : 1 - progress;
};
var createLumiereCamera = (options) => {
  const { width, height, camera } = options;
  const motion = options.animationIntensity === "calm" ? 0.6 : options.animationIntensity === "chaotic" ? 1.4 : 1;
  const span = { startTime: options.startTime, endTime: options.endTime };
  return (time) => {
    const progress = resolveLumiereCameraProgress(time, span, options.sections);
    const floatX = (Math.sin(time * 0.21 + 0.4) * 0.6 + Math.sin(time * 0.53 + 1.9) * 0.4) * 6e-3 * motion;
    const floatY = (Math.cos(time * 0.17 + 1.1) * 0.6 + Math.sin(time * 0.47 + 0.3) * 0.4) * 6e-3 * motion;
    return {
      x: width / 2 + (camera.driftX * progress + floatX) * width,
      y: height / 2 + (camera.driftY * progress + floatY) * height,
      pivotX: width / 2,
      pivotY: height / 2,
      scale: (1 + camera.push * progress) * (1 + 8e-3 * motion * Math.sin(time * 0.31 + 0.7)),
      rotation: 4e-3 * motion * Math.sin(time * 0.13 + 2.1)
    };
  };
};

// folia:src/components/visualizer/lumiere/types.ts
var LUMIERE_BLOOM = {
  // 图形组阈值高一些：只让光源与光柱芯发晕，光柱本身不再被抬亮，文字在光里才压得住。
  graphics: { strength: 1.5, threshold: 0.42, knee: 0.3, levels: 6, spread: 0.9 },
  // 文字组：原来的 1.9 × 调试时试出的 0.6（可读性最好）。
  text: { strength: 1.15, threshold: 0.12, knee: 0.2, levels: 5, spread: 0.95 }
};

// folia:src/components/visualizer/lumiere/scene.ts
var lumiereScaleMask13 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET13 = (1354289308 ^ lumiereScaleMask13) + Math.imul(4034148709 ^ lumiereScaleMask13, 699505802 ^ lumiereScaleMask13) - ((1354289308 ^ lumiereScaleMask13) + Math.imul(4034148709 ^ lumiereScaleMask13, 699505802 ^ lumiereScaleMask13));
var HANDOFF = 0.9 + LUMIERE_NEUTRAL_OFFSET13;
var GLARE_MOVE = 1.6;
var easeInOutCubic2 = (value) => {
  const t = Math.min(1, Math.max(0, value));
  return t < 0.5 ? 4 * t ** 3 : 1 - (-2 * t + 2) ** 3 / 2;
};
var smooth4 = (value) => {
  const t = Math.min(1, Math.max(0, value));
  return t * t * (3 - 2 * t);
};
var lerp2 = (a, b, k) => a + (b - a) * k;
var LUMIERE_SHADER_NO_DARK = [0, 0, 0, 0];
var UNLIT_COOL = [0.62, 0.68, 0.8];
var glowOf = (rgb, fallback) => {
  const peak = Math.max(...rgb);
  return peak < 0.04 ? fallback : scaleRgb(rgb, 1 / peak);
};
var resolveLumierePalette = (theme, themeMix = 0) => {
  const mix = Math.min(1, Math.max(0, themeMix));
  const accent = rgbOf(theme.accentColor, CHAMPAGNE);
  let light = mixRgb(mixRgb(CHAMPAGNE, accent, 0.18), glowOf(accent, CHAMPAGNE), mix);
  const peak = Math.max(...light, 1e-3);
  light = scaleRgb(light, 1 / peak);
  const warmLit = mixRgb(light, WHITE, 0.2);
  const primary = glowOf(rgbOf(theme.primaryColor, warmLit), warmLit);
  const secondary = theme.secondaryColor ? glowOf(rgbOf(theme.secondaryColor, primary), primary) : primary;
  return {
    light,
    lit: mixRgb(warmLit, mixRgb(primary, WHITE, 0.2), mix),
    unlit: mixRgb(mixRgb(light, UNLIT_COOL, 0.55), mixRgb(secondary, UNLIT_COOL, 0.35), mix)
  };
};
var blendRig = (from, to, k, glareK) => ({
  beams: [],
  fog: {
    density: lerp2(from.fog.density, to.fog.density, k),
    tyndallBase: lerp2(from.fog.tyndallBase, to.fog.tyndallBase, k),
    scale: lerp2(from.fog.scale, to.fog.scale, k),
    driftX: lerp2(from.fog.driftX, to.fog.driftX, k),
    driftY: lerp2(from.fog.driftY, to.fog.driftY, k),
    warp: lerp2(from.fog.warp, to.fog.warp, k),
    ambient: lerp2(from.fog.ambient, to.fog.ambient, k)
  },
  // 光源移动走自己的缓动曲线（glareK），起步与到位都慢，不是匀速滑过去。
  glare: from.glare && to.glare ? {
    x: lerp2(from.glare.x, to.glare.x, glareK),
    y: lerp2(from.glare.y, to.glare.y, glareK),
    radius: lerp2(from.glare.radius, to.glare.radius, glareK),
    intensity: lerp2(from.glare.intensity, to.glare.intensity, glareK),
    streak: lerp2(from.glare.streak, to.glare.streak, glareK)
  } : k < 0.5 ? from.glare && { ...from.glare, intensity: from.glare.intensity * (1 - k * 2) } : to.glare && { ...to.glare, intensity: to.glare.intensity * (k * 2 - 1) },
  // 焦散与干涉：前半段是上一个光位的（渐弱），后半段是新光位的（渐强）。
  caustic: fadeCaustic(k < 0.5 ? from.caustic : to.caustic, k < 0.5 ? 1 - k * 2 : k * 2 - 1),
  wave: k < 0.5 ? from.wave && { ...from.wave, strength: from.wave.strength * (1 - k * 2) } : to.wave && { ...to.wave, strength: to.wave.strength * (k * 2 - 1) }
});
var fadeCaustic = (caustic2, k) => caustic2 && {
  ...caustic2,
  inBeam: caustic2.inBeam * k,
  floor: caustic2.floor && { ...caustic2.floor, strength: caustic2.floor.strength * k }
};
var createLumiereScene = (pixi, options) => {
  const { width, height, tuning, sprites } = options;
  const aspect = width / height;
  const palette = resolveLumierePalette(options.theme, tuning.themeColorMix);
  const shots = options.shots.length > 0 ? options.shots : [];
  const lead = resolveLumiereLeadShot(shots).profile;
  const rigs = shots.map((shot, index) => shot.profile.light({ aspect, random: createRng(`${options.seed}:${index}:${shot.profile.kind}:light`) }));
  const view = new pixi.Container();
  const stage2 = new pixi.Container();
  view.addChild(stage2);
  const graphics = new pixi.Container();
  const overscan = Math.ceil(Math.max(width, height) * 0.02);
  const field = createLightField(pixi, width, height, overscan);
  const lineArts = shots.map((shot, index) => createLineArt(pixi, {
    height,
    spec: shot.profile.lineArt({ aspect, random: createRng(`${options.seed}:${index}:${shot.profile.kind}:art`) }),
    starTexture: sprites.star
  }));
  const lineArtHolder = new pixi.Container();
  lineArts.forEach((layer) => lineArtHolder.addChild(layer.view));
  lineArtHolder.visible = tuning.lineArt;
  const textRegion = { cx: lead.region.cx * aspect, cy: lead.region.cy, w: lead.region.w * aspect, h: lead.region.h };
  const iconArts = buildShotIconArts({
    icons: options.theme.lyricsIcons,
    enabled: tuning.themeIcons && !tuning.textOnly,
    shotKinds: shots.map((shot) => shot.profile.kind),
    seed: options.seed,
    aspect,
    avoid: textRegion
  }).map((spec) => createLineArt(pixi, { height, spec, starTexture: sprites.star }));
  const iconHolder = new pixi.Container();
  iconArts.forEach((layer) => iconHolder.addChild(layer.view));
  const motes = createMotes(pixi, {
    width,
    height,
    seed: `${options.seed}:motes`,
    texture: sprites.dot,
    spec: { ...lead.motes, count: Math.round(lead.motes.count * tuning.moteAmount) }
  });
  const baseStarfall = lead.starfall ?? null;
  const unitDuration = options.endTime - options.startTime;
  const canOpen = options.opening && unitDuration >= 2 && !tuning.textOnly;
  const starfallSpec = baseStarfall && canOpen ? { ...baseStarfall, opening: Math.min(baseStarfall.opening, Math.max(0.8, unitDuration * 0.4)) } : baseStarfall;
  const starfall = starfallSpec ? createStarfall(pixi, {
    width,
    height,
    seed: options.seed,
    spec: starfallSpec,
    dot: sprites.dot,
    star: sprites.star,
    streak: sprites.streak
  }) : null;
  const opening = canOpen && starfallSpec !== null;
  const ignition = opening ? starfallIgnition(starfallSpec) : 0;
  const starOffset = starfallSpec && !opening ? starfallSpec.opening + 20 : 0;
  const echoSpec = lead.echo ?? { size: 0.34 };
  const keywords = prepareLumiereKeywords(options.theme.wordColors, tuning.keywordColors);
  const echo = tuning.echo > 0 && !tuning.textOnly ? createLyricEcho(pixi, {
    width,
    height,
    lines: options.lines,
    font: resolveThemeFontStack(options.theme),
    weight: resolveThemeFontWeight(options.theme, 500),
    resolution: options.resolution,
    seed: options.seed,
    size: echoSpec.size,
    opacity: tuning.echo,
    keywords
  }) : null;
  graphics.addChild(
    field.view,
    ...echo ? [echo.view] : [],
    ...starfall ? [starfall.view] : [],
    lineArtHolder,
    iconHolder,
    motes.view
  );
  graphics.filterArea = new pixi.Rectangle(-overscan, -overscan, width + overscan * 2, height + overscan * 2);
  const mid = new pixi.Container();
  const typographyOfLine = lumiereTypographyOfLine(shots);
  const window2 = createLyricWindow(pixi, {
    width,
    height,
    lines: options.lines,
    font: resolveThemeFontStack(options.theme),
    weight: resolveThemeFontWeight(options.theme, 500),
    resolution: options.resolution,
    region: {
      cx: lead.region.cx * aspect,
      cy: lead.region.cy,
      w: lead.region.w * aspect,
      h: lead.region.h
    },
    heroPx: globalThis.tfnLyricScale > 1 ? Math.max(28, lead.heroSize * height * globalThis.tfnLyricScale) : lead.heroSize * height,
    neighbors: tuning.windowNeighbors,
    tfnArrivalElapsed: options.tfnArrivalElapsed,
    typography: globalThis.tfnLyricScale > 1 ? "horizontal" : options.typography ?? lead.typography,
    typographyOf: globalThis.tfnLyricScale > 1 || options.typography ? void 0 : typographyOfLine,
    decay: { ...lead.decay, strength: lead.decay.strength * tuning.decay },
    alwaysFly: tuning.trails,
    seed: options.seed,
    sprites,
    letterSpacing: 0.04,
    keywords
  });
  const burstTriggers = shots.flatMap((shot, shotIndex) => {
    const spec = shot.profile.burst ?? null;
    if (!spec) return [];
    const covered = new Set(shot.lines);
    const color = mixRgb(palette.light, spec.tint, 0.85);
    return planBursts(
      spec,
      options.lines.map((_, lineIndex) => ({ glyphs: covered.has(lineIndex) ? window2.glyphTimes(lineIndex) : [] })),
      `${options.seed}:${shotIndex}`
    ).map((trigger) => {
      const keyword = window2.glyphKeyword(trigger.lineIndex, trigger.glyphIndex);
      return { ...trigger, size: trigger.size * spec.size, color: keyword ? keywordBurstColor(color, palette.light, keyword) : color };
    });
  }).sort((a, b) => a.time - b.time);
  const burst2 = burstTriggers.length > 0 ? createCrossBurst(pixi, { sprites }) : null;
  const text = new pixi.Container();
  if (burst2) text.addChild(burst2.view);
  text.addChild(window2.view);
  const front = new pixi.Container();
  let frontMotes = null;
  if (lead.front && tuning.frontBokeh && !tuning.textOnly) {
    frontMotes = createMotes(pixi, {
      width,
      height,
      seed: `${options.seed}:front`,
      texture: sprites.bokeh,
      spec: lead.front
    });
    front.addChild(frontMotes.view);
  }
  stage2.addChild(graphics, mid, text, front);
  graphics.renderable = !tuning.textOnly;
  const bloomOf2 = (preset, multiplier, padding) => createBloomFilter(pixi, {
    ...preset,
    strength: preset.strength * multiplier,
    padding,
    tint: [1, 1, 1]
  });
  const graphicsBloom = bloomOf2(LUMIERE_BLOOM.graphics, tuning.bloom, 0);
  const textBloom = bloomOf2(LUMIERE_BLOOM.text, tuning.textBloom, 0);
  text.filterArea = new pixi.Rectangle(-width, -height, width * 3, height * 3);
  graphics.filters = tuning.bloom > 0 ? [graphicsBloom] : [];
  text.filters = tuning.textBloom > 0 ? [textBloom] : [];
  const lightHex = hexOf(palette.light);
  const rest = { x: width / 2, y: height / 2, pivotX: width / 2, pivotY: height / 2, scale: 1, rotation: 0 };
  const camera = createLumiereCamera({
    width,
    height,
    camera: lead.camera,
    startTime: options.startTime,
    endTime: options.endTime,
    sections: options.sections,
    animationIntensity: options.theme.animationIntensity
  });
  const activeShot = (time) => {
    let index = 0;
    for (let i = 0; i < shots.length; i += 1) if (shots[i].startTime <= time) index = i;
    return index;
  };
  const update = (time) => {
    const local = time - options.startTime;
    const enter = opening ? smooth4((local - ignition + 0.4) / 1.6) : 1;
    const ignite = opening && local >= ignition ? 1.8 * Math.exp(-(local - ignition) / 0.35) : 0;
    const fadeOut = options.fadeOut;
    const exit = fadeOut ? 1 - smooth4((time - fadeOut.start) / Math.max(fadeOut.end - fadeOut.start, 0.05)) : 1;
    const intensity = enter * exit;
    const transform = camera(time);
    stage2.pivot.set(transform.pivotX, transform.pivotY);
    stage2.position.set(transform.x, transform.y);
    stage2.scale.set(transform.scale);
    stage2.rotation = transform.rotation;
    const events = [];
    let boost = 0;
    for (const trigger of burstTriggers) {
      const age = time - trigger.time;
      if (age < 0 || age > BURST_DURATION) continue;
      boost += burstLightBoost(age);
      if (events.length < MAX_BURSTS) {
        const anchor = window2.glyphAnchor(trigger.lineIndex, trigger.glyphIndex, time);
        events.push({
          age,
          x: anchor.x,
          y: anchor.y + anchor.fontPx * trigger.dy,
          length: anchor.fontPx * trigger.size,
          color: trigger.color
        });
      }
    }
    boost = Math.min(boost, 0.45);
    burst2?.update(events);
    const audio = options.audioAt?.(time) ?? { bass: 0, treble: 0, power: 0 };
    const response = tuning.audioResponse;
    const index = activeShot(time);
    const sinceShot = time - shots[index].startTime;
    const handoff = index > 0 ? smooth4(sinceShot / HANDOFF) : 1;
    const glareK = index > 0 ? easeInOutCubic2(sinceShot / GLARE_MOVE) : 1;
    const drive = (shotIndex, weight) => ({
      intensity: intensity * tuning.lightIntensity * (1 + boost) * weight,
      bass: Math.min(1, audio.bass) * response,
      color: palette.light,
      local: time - shots[shotIndex].startTime
    });
    let beams = resolveBeams(rigs[index], time, aspect, drive(index, handoff));
    let rig2 = rigs[index];
    if (handoff < 1) {
      const previous = resolveBeams(rigs[index - 1], time, aspect, drive(index - 1, 1 - handoff));
      beams = [...beams, ...previous].sort((a, b) => b.intensity - a.intensity).slice(0, MAX_BEAMS);
    }
    if (handoff < 1 || glareK < 1) rig2 = blendRig(rigs[index - 1], rigs[index], handoff, glareK);
    if (!tuning.textOnly) {
      field.update({
        beams,
        rig: rig2,
        time,
        // 整体响度让烟雾浓一点（最多 +20%）。
        fogScale: tuning.fogDensity * (1 + boost * 0.5) * (1 + 0.2 * Math.min(1, audio.power) * response),
        color: palette.light,
        glareScale: intensity * tuning.lightIntensity * (1 + boost * 1.5 + ignite),
        dark: LUMIERE_SHADER_NO_DARK,
        octaves: tuning.fogOctaves,
        // 字排在领头光位的文字区里（整个单元一份）。
        textRegion: lead.region
      });
      echo?.update({ time, beams, color: lightHex, intensity: smooth4(local / 1.2) * exit });
      starfall?.update(local + starOffset, time, beams, lightHex, exit);
      lineArts.forEach((layer, shotIndex) => {
        const shot = shots[shotIndex];
        const begin = shotIndex === 0 ? options.startTime + ignition - 0.6 : shot.startTime - 0.6;
        const out = shotIndex === shots.length - 1 ? 1 : 1 - smooth4((time - shot.endTime) / 0.8);
        const base = smooth4((time - begin) / 1.2) * out * exit;
        const draw = (time - begin) / 3.6;
        const fade = base * (shot.profile.artGain ?? 1);
        const nextUse = time < begin ? begin : time <= shot.endTime + 0.8 ? time : Number.POSITIVE_INFINITY;
        const artShown = fade > 3e-3;
        showLineArtLayer(lineArtHolder, lineArts, shotIndex, artShown);
        if (artShown) layer.update(time, draw, fade, beams, lightHex);
        else layer.idle(time, nextUse);
        const icons2 = iconArts[shotIndex];
        if (icons2) {
          const iconsShown = base > 3e-3;
          showLineArtLayer(iconHolder, iconArts, shotIndex, iconsShown);
          if (iconsShown) icons2.update(time, draw, base, beams, lightHex);
          else icons2.idle(time, nextUse);
        }
      });
      motes.update(time, beams, lightHex, exit * (1 + 0.5 * Math.min(1, audio.treble) * response));
      frontMotes?.update(time, beams, lightHex, exit);
    }
    window2.update({
      time,
      beams,
      litColor: palette.lit,
      unlitColor: palette.unlit,
      unlitAlpha: tuning.unlitOpacity,
      intensity: smooth4(Math.min(local, options.tfnArrivalElapsed?.() ?? Infinity) / 0.6) * exit,
      hideTrails: tuning.hideTrails
    });
  };
  return {
    view,
    graphics,
    mid,
    text,
    front,
    burstTimes: burstTriggers.map((trigger) => trigger.time),
    lineAnchor: window2.lineAnchor,
    camera,
    rest,
    update,
    destroy: () => {
      graphics.filters = [];
      text.filters = [];
      graphicsBloom.destroy();
      textBloom.destroy();
      field.destroy();
      lineArts.forEach((layer) => layer.destroy());
      iconArts.forEach((layer) => layer.destroy());
      motes.destroy();
      frontMotes?.destroy();
      burst2?.destroy();
      starfall?.destroy();
      echo?.destroy();
      window2.destroy();
      view.destroy({ children: true });
    }
  };
};

// folia:src/components/visualizer/lumiere/lineart/recipes.ts
var lumiereScaleMask14 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET14 = (523 ^ lumiereScaleMask14) + Math.imul(47868 ^ lumiereScaleMask14, 15875 ^ lumiereScaleMask14) - ((523 ^ lumiereScaleMask14) + Math.imul(47868 ^ lumiereScaleMask14, 15875 ^ lumiereScaleMask14));
var arcPoints = (cx, cy, r, from, to, steps = 64 + LUMIERE_NEUTRAL_OFFSET14) => Array.from({ length: steps + 1 }, (_, i) => {
  const a = from + (to - from) * i / steps;
  return [cx + Math.cos(a) * r, cy + Math.sin(a) * r];
});
var cubicPoints = (p0, p1, p2, p3, steps = 40) => Array.from({ length: steps + 1 }, (_, i) => {
  const t = i / steps;
  const u = 1 - t;
  const a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
  return [
    a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
    a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]
  ];
});
var line = (a, b) => [a, b];
var mergeSpecs = (...specs) => ({
  paths: specs.flatMap((spec) => spec.paths),
  nodes: specs.flatMap((spec) => spec.nodes)
});
var protractorHalo = (options) => {
  const { cx, cy, radius } = options;
  const delay = options.delay ?? 0;
  const alpha = options.alpha ?? 0.5;
  const from = Math.PI * 0.04;
  const to = Math.PI * 0.96;
  const inner = radius * 0.62;
  const paths = [
    { points: arcPoints(cx, cy, radius, to, from, 96), width: 16e-4, alpha, delay, span: 0.45 },
    { points: arcPoints(cx, cy, inner, from, to, 72), width: 13e-4, alpha: alpha * 0.8, delay: delay + 0.08, span: 0.4 },
    { points: arcPoints(cx, cy, radius * 1.18, from + 0.1, to - 0.1, 80), width: 11e-4, alpha: alpha * 0.45, delay: delay + 0.2, span: 0.4, dash: [4e-3, 9e-3] }
  ];
  const step = options.spokeStep ?? Math.PI / 12;
  const nodes = [];
  let index = 0;
  for (let a = Math.PI / 2 - step * 5; a <= Math.PI / 2 + step * 5 + 1e-6; a += step) {
    const long = index % 2 === 0;
    const r0 = inner * 0.2;
    const r1 = radius * (long ? 1.12 : 1.02);
    paths.push({
      points: line([cx + Math.cos(a) * r0, cy + Math.sin(a) * r0], [cx + Math.cos(a) * r1, cy + Math.sin(a) * r1]),
      width: long ? 13e-4 : 9e-4,
      alpha: alpha * (long ? 0.7 : 0.45),
      delay: delay + 0.12 + Math.abs(a - Math.PI / 2) * 0.12,
      span: 0.3
    });
    if (long) nodes.push({ at: [cx + Math.cos(a) * radius, cy + Math.sin(a) * radius], size: 0.022, delay: delay + 0.45, twinklePhase: index * 1.7 });
    index += 1;
  }
  for (let a = from; a <= to; a += Math.PI / 72) {
    paths.push({
      points: line([cx + Math.cos(a) * radius, cy + Math.sin(a) * radius], [cx + Math.cos(a) * radius * 0.975, cy + Math.sin(a) * radius * 0.975]),
      width: 8e-4,
      alpha: alpha * 0.4,
      delay: delay + 0.25 + (a - from) * 0.05,
      span: 0.15
    });
  }
  return { paths, nodes };
};
var viewfinderFrame = (options) => {
  const { aspect, top, bottom } = options;
  const left = options.left * aspect;
  const right = options.right * aspect;
  const delay = options.delay ?? 0;
  const alpha = options.alpha ?? 0.3;
  const corner = 0.03;
  const paths = [
    { points: [[left, top], [right, top], [right, bottom], [left, bottom], [left, top]], width: 9e-4, alpha: alpha * 0.55, delay, span: 0.6 }
  ];
  const corners = [
    [[left, top + corner], [left, top], [left + corner, top]],
    [[right - corner, top], [right, top], [right, top + corner]],
    [[right, bottom - corner], [right, bottom], [right - corner, bottom]],
    [[left + corner, bottom], [left, bottom], [left, bottom - corner]]
  ];
  corners.forEach((points, i) => paths.push({ points, width: 18e-4, alpha, delay: delay + 0.1 + i * 0.05, span: 0.2 }));
  const ticks = 12;
  for (let i = 1; i < ticks; i += 1) {
    const x = left + (right - left) * i / ticks;
    const y = top + (bottom - top) * i / ticks;
    const len = i % 3 === 0 ? 0.014 : 7e-3;
    paths.push({ points: line([x, top], [x, top + len]), width: 8e-4, alpha: alpha * 0.6, delay: delay + 0.3 + i * 0.01, span: 0.1 });
    paths.push({ points: line([x, bottom], [x, bottom - len]), width: 8e-4, alpha: alpha * 0.6, delay: delay + 0.3 + i * 0.01, span: 0.1 });
    paths.push({ points: line([left, y], [left + len, y]), width: 8e-4, alpha: alpha * 0.6, delay: delay + 0.3 + i * 0.01, span: 0.1 });
    paths.push({ points: line([right, y], [right - len, y]), width: 8e-4, alpha: alpha * 0.6, delay: delay + 0.3 + i * 0.01, span: 0.1 });
  }
  const guideX = [left + (right - left) * 0.14, right - (right - left) * 0.14];
  guideX.forEach((x, i) => paths.push({
    points: line([x, top + 0.06], [x, bottom - 0.06]),
    width: 1e-3,
    alpha: alpha * 0.5,
    delay: delay + 0.35 + i * 0.05,
    span: 0.4,
    dash: [3e-3, 0.012]
  }));
  return { paths, nodes: [] };
};
var sprout = (options) => {
  const { cx, baseY, size } = options;
  const delay = options.delay ?? 0;
  const alpha = options.alpha ?? 0.55;
  const open = options.open ?? 1;
  const paths = [
    { points: cubicPoints([cx, 1.04], [cx + 0.01, 0.94], [cx - 8e-3, baseY + 0.08], [cx, baseY]), width: 16e-4, alpha, delay, span: 0.3 }
  ];
  const nodes = [];
  const leaf = (side, index) => {
    const lean = (0.2 + 0.2 * open) * Math.PI;
    const d = [Math.sin(lean) * side, -Math.cos(lean)];
    const n = [-d[1], d[0]];
    const base = [cx, baseY];
    const tip = [base[0] + d[0] * size, base[1] + d[1] * size - size * 0.12];
    const bulge = size * 0.34;
    const at = (along, across) => [
      base[0] + d[0] * size * along + n[0] * across,
      base[1] + d[1] * size * along + n[1] * across - size * 0.12 * along * along
    ];
    const leafDelay = delay + 0.22 + index * 0.08;
    paths.push({ points: cubicPoints(base, at(0.3, bulge), at(0.78, bulge * 0.9), tip, 48), width: 26e-4, alpha, delay: leafDelay, span: 0.35 });
    paths.push({ points: cubicPoints(base, at(0.3, -bulge * 0.95), at(0.8, -bulge * 0.6), tip, 48), width: 26e-4, alpha, delay: leafDelay + 0.04, span: 0.35 });
    paths.push({ points: cubicPoints(base, at(0.35, bulge * 0.08), at(0.7, bulge * 0.05), tip, 32), width: 11e-4, alpha: alpha * 0.7, delay: leafDelay + 0.12, span: 0.3 });
    for (let v = 1; v <= 4; v += 1) {
      const f = v / 5.2;
      const start = at(f, bulge * 0.04);
      for (const s of [1, -1]) {
        const end = at(f + 0.14, s * bulge * (0.72 - f * 0.35));
        paths.push({ points: cubicPoints(start, at(f + 0.04, s * bulge * 0.25), at(f + 0.1, s * bulge * 0.5), end, 16), width: 8e-4, alpha: alpha * 0.45, delay: leafDelay + 0.2 + v * 0.03, span: 0.18 });
      }
    }
    nodes.push({ at: tip, size: 0.03, delay: leafDelay + 0.3, twinklePhase: index * 2.1 });
    nodes.push({ at: at(0.45, bulge * 0.86), size: 0.014, delay: leafDelay + 0.33, twinklePhase: index * 2.1 + 1 });
    nodes.push({ at: at(0.6, -bulge * 0.8), size: 0.012, delay: leafDelay + 0.36, twinklePhase: index * 2.1 + 2 });
  };
  leaf(-1, 0);
  leaf(1, 1);
  nodes.push({ at: [cx, baseY], size: 0.02, delay: delay + 0.3, twinklePhase: 0.5 });
  return { paths, nodes };
};
var scatteredSparks = (options) => {
  const [x0, y0, x1, y1] = options.region ?? [0.05, 0.08, 0.95, 0.92];
  const nodes = Array.from({ length: options.count }, (_, i) => ({
    at: [(x0 + (x1 - x0) * options.random()) * options.aspect, y0 + (y1 - y0) * options.random()],
    size: 6e-3 + options.random() * 0.012,
    delay: (options.delay ?? 0) + options.random() * 0.5,
    twinklePhase: i * 2.399
  }));
  return { paths: [], nodes };
};
var blindsWindow = (options) => {
  const { x, y, w, h, slats } = options;
  const delay = options.delay ?? 0;
  const alpha = options.alpha ?? 0.5;
  const paths = [
    { points: [[x, y], [x + w, y], [x + w, y + h], [x, y + h], [x, y]], width: 18e-4, alpha, delay, span: 0.5 }
  ];
  for (let i = 1; i < slats; i += 1) {
    const sy = y + h * i / slats;
    paths.push({ points: line([x, sy], [x + w, sy]), width: 1e-3, alpha: alpha * 0.6, delay: delay + 0.1 + i * 0.03, span: 0.2 });
  }
  return { paths, nodes: [{ at: [x + w, y + h], size: 0.018, delay: delay + 0.4, twinklePhase: 1 }] };
};
var prismTriangle = (options) => {
  const { cx, cy, size } = options;
  const h = size * Math.sqrt(3) / 2;
  const top = [cx, cy - h * 2 / 3];
  const left = [cx - size / 2, cy + h / 3];
  const right = [cx + size / 2, cy + h / 3];
  const alpha = options.alpha ?? 0.7;
  const delay = options.delay ?? 0;
  return {
    paths: [
      { points: [top, right, left, top], width: 22e-4, alpha, delay, span: 0.5 },
      { points: [top, [cx, cy + h / 3]], width: 8e-4, alpha: alpha * 0.4, delay: delay + 0.3, span: 0.3, dash: [4e-3, 8e-3] }
    ],
    nodes: [top, left, right].map((at, i) => ({ at, size: 0.02, delay: delay + 0.4 + i * 0.05, twinklePhase: i * 1.3 }))
  };
};
var slitBarrier = (options) => {
  const { cx, y, width, gap, separation } = options;
  const alpha = options.alpha ?? 0.6;
  const delay = options.delay ?? 0;
  const a = cx - separation / 2;
  const b = cx + separation / 2;
  const segments = [[cx - width / 2, a - gap / 2], [a + gap / 2, b - gap / 2], [b + gap / 2, cx + width / 2]];
  return {
    paths: segments.map(([from, to], i) => ({ points: line([from, y], [to, y]), width: 26e-4, alpha, delay: delay + i * 0.08, span: 0.3 })),
    nodes: [a, b].map((x, i) => ({ at: [x, y], size: 0.022, delay: delay + 0.35 + i * 0.05, twinklePhase: i * 2 }))
  };
};

// folia:src/components/visualizer/lumiere/lineart/diagrams.ts
var lumiereScaleMask15 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET15 = (15230 ^ lumiereScaleMask15) + Math.imul(10553 ^ lumiereScaleMask15, 3118931976 ^ lumiereScaleMask15) - ((15230 ^ lumiereScaleMask15) + Math.imul(10553 ^ lumiereScaleMask15, 3118931976 ^ lumiereScaleMask15));
var TAU = Math.PI * (2 + LUMIERE_NEUTRAL_OFFSET15);
var path = (points, style = {}) => ({
  points,
  width: style.width ?? 16e-4,
  alpha: style.alpha ?? 0.55,
  delay: style.delay ?? 0,
  span: style.span ?? 0.4,
  ...style.dash ? { dash: style.dash } : {}
});
var node = (at, size = 0.018, delay = 0.4, twinklePhase = 0) => ({ at, size, delay, twinklePhase });
var segment = (a, b, style = {}) => path([a, b], style);
var ellipsePath = (cx, cy, rx, ry, rotation = 0, from = 0, to = TAU, steps = 96) => {
  const cos = Math.cos(rotation);
  const sin = Math.sin(rotation);
  return arcPoints(0, 0, 1, from, to, steps).map(([x, y]) => [cx + x * rx * cos - y * ry * sin, cy + x * rx * sin + y * ry * cos]);
};
var circle = (cx, cy, r, style = {}) => path(ellipsePath(cx, cy, r, r), style);
var merge = (...specs) => ({
  paths: specs.flatMap((spec) => spec.paths),
  nodes: specs.flatMap((spec) => spec.nodes)
});
var rays = (cx, cy, r0, r1, count, from = 0, to = TAU, style = {}) => ({
  paths: Array.from({ length: count }, (_, i) => {
    const a = from + (to - from) * (i + (to - from >= TAU - 1e-6 ? 0 : 0.5)) / count;
    return segment([cx + Math.cos(a) * r0, cy + Math.sin(a) * r0], [cx + Math.cos(a) * r1, cy + Math.sin(a) * r1], {
      width: 1e-3,
      alpha: 0.4,
      ...style,
      delay: (style.delay ?? 0) + i / count * 0.3,
      span: style.span ?? 0.2
    });
  }),
  nodes: []
});
var concentric = (cx, cy, radii, style = {}) => ({
  paths: radii.map((r, i) => circle(cx, cy, r, { width: 11e-4, alpha: 0.45, ...style, delay: (style.delay ?? 0) + i * 0.06 })),
  nodes: []
});
var crossWindow = (x, y, w, h, style = {}) => ({
  paths: [
    path([[x, y], [x + w, y], [x + w, y + h], [x, y + h], [x, y]], { width: 2e-3, alpha: 0.55, ...style }),
    segment([x + w / 2, y], [x + w / 2, y + h], { width: 14e-4, alpha: 0.45, delay: (style.delay ?? 0) + 0.15 }),
    segment([x, y + h / 2], [x + w, y + h / 2], { width: 14e-4, alpha: 0.45, delay: (style.delay ?? 0) + 0.2 })
  ],
  nodes: [node([x + w / 2, y + h / 2], 0.02, (style.delay ?? 0) + 0.4)]
});
var archWindow = (x, y, w, h, style = {}) => {
  const r = w / 2;
  const top = y + r;
  return {
    paths: [
      path([[x, y + h], [x, top], ...arcPoints(x + r, top, r, Math.PI, TAU, 40), [x + w, y + h], [x, y + h]], { width: 18e-4, alpha: 0.55, ...style }),
      segment([x + r, y], [x + r, y + h], { width: 1e-3, alpha: 0.35, delay: (style.delay ?? 0) + 0.2 })
    ],
    nodes: [node([x + r, y + 0.01], 0.018, (style.delay ?? 0) + 0.4)]
  };
};
var roseWindow = (cx, cy, r, style = {}) => merge(
  concentric(cx, cy, [r, r * 0.62, r * 0.22], { width: 16e-4, alpha: 0.55, ...style }),
  rays(cx, cy, r * 0.22, r, 12, 0, TAU, { delay: (style.delay ?? 0) + 0.2 }),
  {
    paths: Array.from({ length: 12 }, (_, i) => {
      const a = i / 12 * TAU;
      return circle(cx + Math.cos(a) * r * 0.8, cy + Math.sin(a) * r * 0.8, r * 0.14, { width: 9e-4, alpha: 0.35, delay: (style.delay ?? 0) + 0.35 + i * 0.02 });
    }),
    nodes: [node([cx, cy], 0.028, (style.delay ?? 0) + 0.5)]
  }
);
var doorSlit = (cx, top, bottom, gap, style = {}) => ({
  paths: [
    segment([cx - gap / 2, top], [cx - gap / 2, bottom], { width: 18e-4, alpha: 0.55, ...style }),
    segment([cx + gap / 2, top], [cx + gap / 2, bottom], { width: 18e-4, alpha: 0.55, ...style, delay: (style.delay ?? 0) + 0.05 }),
    segment([cx - gap / 2 - 0.25, bottom], [cx + gap / 2 + 0.25, bottom], { width: 1e-3, alpha: 0.35, delay: (style.delay ?? 0) + 0.2 })
  ],
  nodes: [node([cx, top + 0.02], 0.02, (style.delay ?? 0) + 0.4)]
});
var gridPanel = (x, y, w, h, cols, rows, diagonal = false, style = {}) => {
  const paths = [path([[x, y], [x + w, y], [x + w, y + h], [x, y + h], [x, y]], { width: 18e-4, alpha: 0.5, ...style })];
  const inner = { width: 9e-4, alpha: 0.32, delay: (style.delay ?? 0) + 0.15, span: 0.25 };
  if (diagonal) {
    const n = cols + rows;
    for (let i = 1; i < n; i += 1) {
      const t = i / n;
      paths.push(segment([x + w * Math.min(1, t * 2), y + h * Math.max(0, t * 2 - 1)], [x + w * Math.max(0, t * 2 - 1), y + h * Math.min(1, t * 2)], inner));
      paths.push(segment([x + w * (1 - Math.min(1, t * 2)), y + h * Math.max(0, t * 2 - 1)], [x + w * (1 - Math.max(0, t * 2 - 1)), y + h * Math.min(1, t * 2)], inner));
    }
  } else {
    for (let i = 1; i < cols; i += 1) paths.push(segment([x + w * i / cols, y], [x + w * i / cols, y + h], inner));
    for (let j = 1; j < rows; j += 1) paths.push(segment([x, y + h * j / rows], [x + w, y + h * j / rows], inner));
  }
  return { paths, nodes: [] };
};
var tallWindows = (x0, x1, y, h, count, style = {}) => merge(
  ...Array.from({ length: count }, (_, i) => {
    const w = (x1 - x0) / count * 0.45;
    const x = x0 + (x1 - x0) * (i + 0.5) / count - w / 2;
    return archWindow(x, y, w, h, { alpha: 0.45, ...style, delay: (style.delay ?? 0) + i * 0.07 });
  })
);
var shards = (aspect, random, count, style = {}) => ({
  paths: Array.from({ length: count }, (_, i) => {
    const cx = (0.1 + random() * 0.8) * aspect;
    const cy = 0.12 + random() * 0.76;
    const r = 0.025 + random() * 0.05;
    const a = random() * TAU;
    const points = [0, 1, 2, 0].map((k) => [cx + Math.cos(a + k * TAU / 3) * r, cy + Math.sin(a + k * TAU / 3) * r * (0.7 + random() * 0.6)]);
    return path(points, { width: 14e-4, alpha: 0.5, ...style, delay: (style.delay ?? 0) + i * 0.04, span: 0.25 });
  }),
  nodes: []
});
var spectrumLines = (x0, x1, y, h, random, count, style = {}) => ({
  paths: [
    segment([x0, y + h / 2], [x1, y + h / 2], { width: 1e-3, alpha: 0.35, ...style }),
    ...Array.from({ length: count }, (_, i) => {
      const x = x0 + (x1 - x0) * (0.05 + 0.9 * random());
      const k = 0.3 + random() * 0.7;
      return segment([x, y + h / 2], [x, y + h / 2 - h * k], { width: 12e-4 + random() * 12e-4, alpha: 0.4 + k * 0.3, delay: (style.delay ?? 0) + 0.1 + i * 0.03, span: 0.2 });
    })
  ],
  nodes: []
});
var cubeSplitter = (cx, cy, size, style = {}) => ({
  paths: [
    path([[cx - size / 2, cy - size / 2], [cx + size / 2, cy - size / 2], [cx + size / 2, cy + size / 2], [cx - size / 2, cy + size / 2], [cx - size / 2, cy - size / 2]], { width: 2e-3, alpha: 0.6, ...style }),
    segment([cx - size / 2, cy + size / 2], [cx + size / 2, cy - size / 2], { width: 12e-4, alpha: 0.45, delay: (style.delay ?? 0) + 0.2 })
  ],
  nodes: [node([cx, cy], 0.022, (style.delay ?? 0) + 0.35)]
});
var rainbowArcs = (cx, cy, r, style = {}) => ({
  paths: [
    path(arcPoints(cx, cy, r, Math.PI * 1.08, Math.PI * 1.92, 72), { width: 18e-4, alpha: 0.5, ...style }),
    path(arcPoints(cx, cy, r * 1.18, Math.PI * 1.1, Math.PI * 1.9, 72), { width: 1e-3, alpha: 0.3, delay: (style.delay ?? 0) + 0.15, dash: [6e-3, 0.01] }),
    circle(cx, cy - r * 0.4, 0.03, { width: 12e-4, alpha: 0.45, delay: (style.delay ?? 0) + 0.3 })
  ],
  nodes: []
});
var glassCup = (cx, top, w, h, style = {}) => ({
  paths: [
    path(ellipsePath(cx, top, w / 2, w * 0.12), { width: 16e-4, alpha: 0.5, ...style }),
    path([[cx - w / 2, top], [cx - w * 0.4, top + h], [cx + w * 0.4, top + h], [cx + w / 2, top]], { width: 16e-4, alpha: 0.5, delay: (style.delay ?? 0) + 0.1 }),
    path(ellipsePath(cx, top + h, w * 0.4, w * 0.09, 0, 0, Math.PI), { width: 1e-3, alpha: 0.35, delay: (style.delay ?? 0) + 0.2 })
  ],
  nodes: [node([cx - w * 0.3, top + h * 0.3], 0.016, (style.delay ?? 0) + 0.35)]
});
var ripples = (cx, cy, r, count, style = {}) => ({
  paths: Array.from({ length: count }, (_, i) => path(ellipsePath(cx, cy, r * (i + 1) / count, r * 0.3 * (i + 1) / count), {
    width: 12e-4,
    alpha: 0.5 - i * 0.07,
    ...style,
    delay: (style.delay ?? 0) + i * 0.08
  })),
  nodes: [node([cx, cy], 0.02, (style.delay ?? 0) + 0.3)]
});
var waterline = (aspect, y, amplitude, waves, style = {}) => ({
  paths: [path(Array.from({ length: 121 }, (_, i) => {
    const x = i / 120 * aspect;
    return [x, y + Math.sin(i / 120 * waves * TAU) * amplitude];
  }), { width: 14e-4, alpha: 0.45, ...style, span: 0.6 })],
  nodes: []
});
var magnifier = (cx, cy, r, style = {}) => ({
  paths: [
    circle(cx, cy, r, { width: 22e-4, alpha: 0.6, ...style }),
    circle(cx, cy, r * 0.9, { width: 9e-4, alpha: 0.3, delay: (style.delay ?? 0) + 0.1 }),
    segment([cx + r * 0.7, cy + r * 0.7], [cx + r * 1.6, cy + r * 1.6], { width: 4e-3, alpha: 0.5, delay: (style.delay ?? 0) + 0.2 })
  ],
  nodes: []
});
var crystal = (cx, cy, r, style = {}) => {
  const outer = Array.from({ length: 7 }, (_, i) => [cx + Math.cos(i * TAU / 6) * r, cy + Math.sin(i * TAU / 6) * r * 1.3]);
  return {
    paths: [
      path(outer, { width: 2e-3, alpha: 0.55, ...style }),
      ...[0, 1, 2].map((i) => segment(outer[i], outer[i + 3], { width: 9e-4, alpha: 0.3, delay: (style.delay ?? 0) + 0.15 + i * 0.05 }))
    ],
    nodes: outer.slice(0, 6).filter((_, i) => i % 2 === 0).map((at, i) => node(at, 0.016, (style.delay ?? 0) + 0.4, i))
  };
};
var lens = (cx, cy, h, convex, aspect, style = {}) => {
  const bulge = h * 0.18;
  const top = [cx, cy - h / 2];
  const bottom = [cx, cy + h / 2];
  const side = (sign) => cubicPoints(top, [cx + sign * (convex ? bulge : -bulge * 0.2) + (convex ? 0 : sign * bulge * 0.6), cy - h / 4], [cx + sign * (convex ? bulge : -bulge * 0.2) + (convex ? 0 : sign * bulge * 0.6), cy + h / 4], bottom, 32);
  const outline = convex ? [...side(1), ...side(-1).reverse()] : [
    [cx - bulge * 0.7, cy - h / 2],
    [cx + bulge * 0.7, cy - h / 2],
    ...cubicPoints([cx + bulge * 0.7, cy - h / 2], [cx + bulge * 0.1, cy - h / 4], [cx + bulge * 0.1, cy + h / 4], [cx + bulge * 0.7, cy + h / 2], 24),
    [cx - bulge * 0.7, cy + h / 2],
    ...cubicPoints([cx - bulge * 0.7, cy + h / 2], [cx - bulge * 0.1, cy + h / 4], [cx - bulge * 0.1, cy - h / 4], [cx - bulge * 0.7, cy - h / 2], 24)
  ];
  return {
    paths: [
      path(outline, { width: 2e-3, alpha: 0.6, ...style }),
      segment([aspect * 0.05, cy], [aspect * 0.95, cy], { width: 9e-4, alpha: 0.3, delay: (style.delay ?? 0) + 0.1, dash: [8e-3, 8e-3], span: 0.5 })
    ],
    nodes: []
  };
};
var rayPath = (points, style = {}) => ({
  paths: [path(points, { width: 14e-4, alpha: 0.6, span: 0.5, ...style })],
  nodes: [node(points[points.length - 1], 0.016, (style.delay ?? 0) + (style.span ?? 0.5), points.length)]
});
var focusMark = (x, y, style = {}) => ({
  paths: [
    segment([x - 0.012, y], [x + 0.012, y], { width: 12e-4, alpha: 0.55, ...style }),
    segment([x, y - 0.012], [x, y + 0.012], { width: 12e-4, alpha: 0.55, ...style })
  ],
  nodes: [node([x, y], 0.024, (style.delay ?? 0) + 0.3)]
});
var mirror = (cx, cy, length, angle, style = {}) => {
  const dx = Math.cos(angle) * length / 2;
  const dy = Math.sin(angle) * length / 2;
  const nx = -Math.sin(angle);
  const ny = Math.cos(angle);
  const hatches = Array.from({ length: 10 }, (_, i) => {
    const t = -0.45 + i / 9 * 0.9;
    const bx = cx + dx * 2 * t;
    const by = cy + dy * 2 * t;
    return segment([bx, by], [bx + nx * 0.015 - dx * 0.04, by + ny * 0.015 - dy * 0.04], { width: 8e-4, alpha: 0.3, delay: (style.delay ?? 0) + 0.2 + i * 0.01, span: 0.1 });
  });
  return {
    paths: [
      segment([cx - dx, cy - dy], [cx + dx, cy + dy], { width: 3e-3, alpha: 0.6, ...style }),
      ...hatches,
      segment([cx, cy], [cx - nx * length * 0.5, cy - ny * length * 0.5], { width: 9e-4, alpha: 0.35, delay: (style.delay ?? 0) + 0.25, dash: [6e-3, 6e-3] }),
      path(arcPoints(cx, cy, length * 0.12, Math.atan2(-ny, -nx) - 0.5, Math.atan2(-ny, -nx) + 0.5, 20), { width: 9e-4, alpha: 0.4, delay: (style.delay ?? 0) + 0.35 })
    ],
    nodes: []
  };
};
var interfaceLine = (aspect, y, style = {}) => ({
  paths: [
    segment([aspect * 0.06, y], [aspect * 0.94, y], { width: 2e-3, alpha: 0.55, ...style, span: 0.5 }),
    ...Array.from({ length: 24 }, (_, i) => {
      const x = aspect * (0.08 + i / 23 * 0.84);
      return segment([x, y + 0.01], [x - 0.02, y + 0.04], { width: 8e-4, alpha: 0.22, delay: (style.delay ?? 0) + 0.2 + i * 0.01, span: 0.1 });
    })
  ],
  nodes: []
});
var ruler = (x0, x1, y, ticks, style = {}) => ({
  paths: [
    segment([x0, y], [x1, y], { width: 16e-4, alpha: 0.5, ...style, span: 0.5 }),
    ...Array.from({ length: ticks + 1 }, (_, i) => {
      const x = x0 + (x1 - x0) * i / ticks;
      const long = i % 5 === 0;
      return segment([x, y], [x, y + (long ? 0.02 : 0.01)], { width: 8e-4, alpha: 0.4, delay: (style.delay ?? 0) + 0.2 + i * 5e-3, span: 0.08 });
    })
  ],
  nodes: []
});
var fiber = (points, thickness, style = {}) => {
  const center = cubicPoints(...points, 60);
  const offset = (sign) => center.map(([x, y], i) => {
    const [nx0, ny0] = center[Math.max(0, i - 1)];
    const [nx1, ny1] = center[Math.min(center.length - 1, i + 1)];
    const dx = nx1 - nx0;
    const dy = ny1 - ny0;
    const len = Math.hypot(dx, dy) || 1;
    return [x - dy / len * thickness * sign, y + dx / len * thickness * sign];
  });
  return {
    paths: [path(offset(1), { width: 14e-4, alpha: 0.5, ...style, span: 0.6 }), path(offset(-1), { width: 14e-4, alpha: 0.5, ...style, delay: (style.delay ?? 0) + 0.05, span: 0.6 })],
    nodes: [node(center[center.length - 1], 0.024, (style.delay ?? 0) + 0.6)]
  };
};
var pinholeBox = (cx, cy, w, h, style = {}) => ({
  paths: [
    path([[cx - w / 2, cy - h / 2], [cx + w / 2, cy - h / 2], [cx + w / 2, cy + h / 2], [cx - w / 2, cy + h / 2], [cx - w / 2, cy - h / 2]], { width: 18e-4, alpha: 0.5, ...style }),
    segment([cx - w / 2 - 0.25, cy - h * 0.35], [cx - w / 2 - 0.25, cy + h * 0.35], { width: 16e-4, alpha: 0.45, delay: (style.delay ?? 0) + 0.1 }),
    segment([cx + w / 2 - 0.02, cy + h * 0.28], [cx + w / 2 - 0.02, cy - h * 0.28], { width: 14e-4, alpha: 0.4, delay: (style.delay ?? 0) + 0.3, dash: [5e-3, 5e-3] }),
    segment([cx - w / 2 - 0.25, cy - h * 0.35], [cx + w / 2 - 0.02, cy + h * 0.28], { width: 8e-4, alpha: 0.3, delay: (style.delay ?? 0) + 0.2 }),
    segment([cx - w / 2 - 0.25, cy + h * 0.35], [cx + w / 2 - 0.02, cy - h * 0.28], { width: 8e-4, alpha: 0.3, delay: (style.delay ?? 0) + 0.2 })
  ],
  nodes: [node([cx - w / 2, cy], 0.02, (style.delay ?? 0) + 0.3)]
});
var rings = (cx, cy, r, count, style = {}) => concentric(
  cx,
  cy,
  Array.from({ length: count }, (_, i) => r * Math.sqrt((i + 1) / count)),
  style
);
var grating = (cx, y, width, slits, style = {}) => ({
  paths: [
    segment([cx - width / 2, y], [cx + width / 2, y], { width: 22e-4, alpha: 0.55, ...style }),
    ...Array.from({ length: slits }, (_, i) => {
      const x = cx - width * 0.3 + width * 0.6 * i / Math.max(1, slits - 1);
      return segment([x, y - 0.01], [x, y + 0.01], { width: 8e-4, alpha: 0.4, delay: (style.delay ?? 0) + 0.15 + i * 0.01, span: 0.1 });
    })
  ],
  nodes: []
});
var twoSources = (cx, cy, separation, r, style = {}) => merge(
  concentric(cx - separation / 2, cy, [r * 0.25, r * 0.5, r * 0.75, r], { alpha: 0.3, ...style }),
  concentric(cx + separation / 2, cy, [r * 0.25, r * 0.5, r * 0.75, r], { alpha: 0.3, ...style, delay: (style.delay ?? 0) + 0.1 }),
  { paths: [], nodes: [node([cx - separation / 2, cy], 0.024, 0.3), node([cx + separation / 2, cy], 0.024, 0.35, 1)] }
);
var moire = (cx, cy, size, count, rotation, style = {}) => {
  const set = (angle, delay) => Array.from({ length: count }, (_, i) => {
    const t = -0.5 + i / (count - 1);
    const ox = Math.cos(angle + Math.PI / 2) * t * size;
    const oy = Math.sin(angle + Math.PI / 2) * t * size;
    return segment([cx + ox - Math.cos(angle) * size / 2, cy + oy - Math.sin(angle) * size / 2], [cx + ox + Math.cos(angle) * size / 2, cy + oy + Math.sin(angle) * size / 2], {
      width: 8e-4,
      alpha: 0.3,
      ...style,
      delay: delay + i * 8e-3,
      span: 0.15
    });
  });
  return { paths: [...set(0, style.delay ?? 0), ...set(rotation, (style.delay ?? 0) + 0.2)], nodes: [] };
};
var standingWave = (x0, x1, y, amplitude, loops, style = {}) => ({
  paths: [-1, -0.5, 0.5, 1].map((k, j) => path(Array.from({ length: 121 }, (_, i) => {
    const t = i / 120;
    return [x0 + (x1 - x0) * t, y + Math.sin(t * loops * Math.PI) * amplitude * k];
  }), { width: 12e-4, alpha: 0.35 + Math.abs(k) * 0.2, ...style, delay: (style.delay ?? 0) + j * 0.06, span: 0.5 })),
  nodes: Array.from({ length: loops + 1 }, (_, i) => node([x0 + (x1 - x0) * i / loops, y], 0.014, (style.delay ?? 0) + 0.5, i))
});
var polarizers = (cx, cy, r, gap, rotation, style = {}) => {
  const disc = (x, angle, delay) => [
    circle(x, cy, r, { width: 16e-4, alpha: 0.5, ...style, delay }),
    ...Array.from({ length: 7 }, (_, i) => {
      const t = -0.75 + i / 6 * 1.5;
      const half = Math.sqrt(Math.max(0, 1 - t * t)) * r;
      const ox = -Math.sin(angle) * t * r;
      const oy = Math.cos(angle) * t * r;
      return segment([x + ox - Math.cos(angle) * half, cy + oy - Math.sin(angle) * half], [x + ox + Math.cos(angle) * half, cy + oy + Math.sin(angle) * half], { width: 8e-4, alpha: 0.3, delay: delay + 0.15 + i * 0.02, span: 0.15 });
    })
  ];
  return { paths: [...disc(cx - gap / 2, 0, style.delay ?? 0), ...disc(cx + gap / 2, rotation, (style.delay ?? 0) + 0.2)], nodes: [] };
};
var bigLeaf = (cx, cy, length, angle, style = {}) => {
  const d = [Math.cos(angle), Math.sin(angle)];
  const n = [-d[1], d[0]];
  const at = (along, across) => [cx + d[0] * length * (along - 0.5) + n[0] * across, cy + d[1] * length * (along - 0.5) + n[1] * across];
  const bulge = length * 0.3;
  const paths = [
    path(cubicPoints(at(0, 0), at(0.3, bulge), at(0.75, bulge * 0.8), at(1, 0), 48), { width: 2e-3, alpha: 0.6, ...style, span: 0.4 }),
    path(cubicPoints(at(0, 0), at(0.3, -bulge), at(0.75, -bulge * 0.8), at(1, 0), 48), { width: 2e-3, alpha: 0.6, ...style, delay: (style.delay ?? 0) + 0.05, span: 0.4 }),
    path([at(-0.12, 0), at(1, 0)], { width: 14e-4, alpha: 0.5, delay: (style.delay ?? 0) + 0.15, span: 0.4 })
  ];
  for (let v = 1; v <= 6; v += 1) {
    const f = v / 7.5;
    for (const s of [1, -1]) {
      paths.push(path(cubicPoints(at(f, 0), at(f + 0.05, s * bulge * 0.3), at(f + 0.1, s * bulge * 0.55), at(f + 0.15, s * bulge * (0.8 - f * 0.35)), 16), {
        width: 9e-4,
        alpha: 0.4,
        delay: (style.delay ?? 0) + 0.25 + v * 0.05,
        span: 0.18
      }));
    }
  }
  return { paths, nodes: [node(at(1, 0), 0.026, (style.delay ?? 0) + 0.6)] };
};
var canopy = (aspect, random, style = {}) => {
  const paths = [];
  const grow = (x, y, angle, length, depth, delay) => {
    const x1 = x + Math.cos(angle) * length;
    const y1 = y + Math.sin(angle) * length;
    paths.push(segment([x, y], [x1, y1], { width: 8e-4 + depth * 5e-4, alpha: 0.3 + depth * 0.08, delay, span: 0.2 }));
    if (depth <= 0) return;
    grow(x1, y1, angle - 0.35 - random() * 0.3, length * 0.72, depth - 1, delay + 0.08);
    grow(x1, y1, angle + 0.35 + random() * 0.3, length * 0.72, depth - 1, delay + 0.08);
  };
  [0.08, 0.35, 0.65, 0.92].forEach((fx, i) => grow(fx * aspect, -0.02, Math.PI / 2 + (random() - 0.5) * 0.6, 0.14, 4, (style.delay ?? 0) + i * 0.05));
  return { paths, nodes: [] };
};
var fernCurl = (cx, cy, r, style = {}) => {
  const spiral = Array.from({ length: 140 }, (_, i) => {
    const t = i / 139;
    const a = t * TAU * 2.2;
    const rr = r * Math.exp(-t * 2.4);
    return [cx + Math.cos(a) * rr, cy + Math.sin(a) * rr];
  });
  const stem = [[cx + r, cy], [cx + r, cy + r * 2.2]];
  const leaflets = Array.from({ length: 9 }, (_, i) => {
    const [x, y] = spiral[Math.floor(i / 9 * 90)];
    return circle(x, y, 8e-3 + (1 - i / 9) * 0.01, { width: 8e-4, alpha: 0.35, delay: (style.delay ?? 0) + 0.4 + i * 0.03, span: 0.1 });
  });
  return { paths: [path(stem, { width: 16e-4, alpha: 0.5, ...style }), path(spiral, { width: 16e-4, alpha: 0.55, ...style, delay: (style.delay ?? 0) + 0.1, span: 0.5 }), ...leaflets], nodes: [] };
};
var seedRoots = (cx, cy, random, style = {}) => ({
  paths: [
    path(ellipsePath(cx, cy, 0.025, 0.035, 0.3), { width: 2e-3, alpha: 0.6, ...style }),
    ...Array.from({ length: 6 }, (_, i) => {
      const spread = (i - 2.5) * 0.05;
      return path(cubicPoints([cx, cy + 0.03], [cx + spread * 0.4, cy + 0.08], [cx + spread, cy + 0.12], [cx + spread * 1.4 + (random() - 0.5) * 0.04, cy + 0.2 + random() * 0.06], 24), {
        width: 9e-4,
        alpha: 0.4,
        delay: (style.delay ?? 0) + 0.2 + i * 0.05,
        span: 0.35
      });
    })
  ],
  nodes: [node([cx, cy - 0.04], 0.03, (style.delay ?? 0) + 0.2)]
});
var bloom = (cx, cy, r, petals, style = {}) => ({
  paths: [
    ...Array.from({ length: petals }, (_, i) => {
      const a = i / petals * TAU;
      const d = [Math.cos(a), Math.sin(a)];
      const n = [-d[1], d[0]];
      const tip = [cx + d[0] * r, cy + d[1] * r];
      const w = r * 0.35;
      return path([
        ...cubicPoints([cx, cy], [cx + d[0] * r * 0.4 + n[0] * w, cy + d[1] * r * 0.4 + n[1] * w], [cx + d[0] * r * 0.9 + n[0] * w * 0.6, cy + d[1] * r * 0.9 + n[1] * w * 0.6], tip, 20),
        ...cubicPoints(tip, [cx + d[0] * r * 0.9 - n[0] * w * 0.6, cy + d[1] * r * 0.9 - n[1] * w * 0.6], [cx + d[0] * r * 0.4 - n[0] * w, cy + d[1] * r * 0.4 - n[1] * w], [cx, cy], 20)
      ], { width: 16e-4, alpha: 0.5, ...style, delay: (style.delay ?? 0) + i * 0.05, span: 0.3 });
    }),
    circle(cx, cy, r * 0.12, { width: 12e-4, alpha: 0.5, delay: (style.delay ?? 0) + 0.4 })
  ],
  nodes: [node([cx, cy], 0.03, (style.delay ?? 0) + 0.5)]
});
var vine = (x, bottom, top, amplitude, turns, style = {}) => ({
  paths: [
    path(Array.from({ length: 161 }, (_, i) => {
      const t = i / 160;
      return [x + Math.sin(t * turns * TAU) * amplitude * (1 - t * 0.4), bottom + (top - bottom) * t];
    }), { width: 16e-4, alpha: 0.55, ...style, span: 0.7 }),
    segment([x, bottom], [x, top], { width: 8e-4, alpha: 0.25, delay: (style.delay ?? 0) + 0.1, dash: [5e-3, 8e-3], span: 0.5 })
  ],
  nodes: [node([x, top], 0.024, (style.delay ?? 0) + 0.7)]
});
var cells = (cx, cy, r, random, count, style = {}) => ({
  paths: [
    circle(cx, cy, r, { width: 22e-4, alpha: 0.5, ...style }),
    ...Array.from({ length: count }, (_, i) => {
      const a = random() * TAU;
      const d = Math.sqrt(random()) * r * 0.8;
      return path(ellipsePath(cx + Math.cos(a) * d, cy + Math.sin(a) * d, 0.012 + random() * 0.012, 8e-3 + random() * 8e-3, random() * Math.PI), {
        width: 9e-4,
        alpha: 0.4,
        delay: (style.delay ?? 0) + 0.15 + i * 0.02,
        span: 0.15
      });
    })
  ],
  nodes: []
});
var molecule = (cx, cy, r, style = {}) => {
  const hex = Array.from({ length: 7 }, (_, i) => [cx + Math.cos(i * TAU / 6 + Math.PI / 6) * r, cy + Math.sin(i * TAU / 6 + Math.PI / 6) * r]);
  return {
    paths: [
      path(hex, { width: 18e-4, alpha: 0.55, ...style }),
      circle(cx, cy, r * 0.55, { width: 1e-3, alpha: 0.35, delay: (style.delay ?? 0) + 0.2 }),
      ...[0, 2, 4].map((k, i) => {
        const [x, y] = hex[k];
        return segment([x, y], [x + (x - cx) * 0.8, y + (y - cy) * 0.8], { width: 12e-4, alpha: 0.45, delay: (style.delay ?? 0) + 0.3 + i * 0.05 });
      })
    ],
    nodes: [0, 2, 4].map((k, i) => {
      const [x, y] = hex[k];
      return node([x + (x - cx) * 0.8, y + (y - cy) * 0.8], 0.02, (style.delay ?? 0) + 0.45, i);
    })
  };
};
var orbits = (cx, cy, radii, tilt, flatten, random, style = {}) => ({
  paths: radii.map((r, i) => path(ellipsePath(cx, cy, r, r * flatten, tilt), { width: 12e-4, alpha: 0.45, ...style, delay: (style.delay ?? 0) + i * 0.07, span: 0.5 })),
  nodes: [
    node([cx, cy], 0.04, (style.delay ?? 0) + 0.2),
    ...radii.map((r, i) => {
      const a = random() * TAU;
      const [x, y] = ellipsePath(cx, cy, r, r * flatten, tilt, a, a, 1)[0];
      return node([x, y], 0.018 + random() * 0.012, (style.delay ?? 0) + 0.5 + i * 0.05, i);
    })
  ]
});
var starTrails = (cx, cy, random, count, maxR, style = {}) => ({
  paths: Array.from({ length: count }, (_, i) => {
    const r = maxR * (0.1 + random() * 0.9);
    const a = random() * TAU;
    const span = 0.4 + random() * 0.8;
    return path(arcPoints(cx, cy, r, a, a + span, 24), { width: 8e-4 + random() * 8e-4, alpha: 0.25 + random() * 0.3, ...style, delay: (style.delay ?? 0) + i / count * 0.4, span: 0.3 });
  }),
  nodes: [node([cx, cy], 0.03, (style.delay ?? 0) + 0.1)]
});
var sextant = (cx, cy, r, style = {}) => merge(
  {
    paths: [
      path(arcPoints(cx, cy, r, Math.PI * 0.33, Math.PI * 0.67, 48), { width: 2e-3, alpha: 0.6, ...style }),
      segment([cx, cy], [cx + Math.cos(Math.PI * 0.33) * r, cy + Math.sin(Math.PI * 0.33) * r], { width: 14e-4, alpha: 0.5, delay: (style.delay ?? 0) + 0.1 }),
      segment([cx, cy], [cx + Math.cos(Math.PI * 0.67) * r, cy + Math.sin(Math.PI * 0.67) * r], { width: 14e-4, alpha: 0.5, delay: (style.delay ?? 0) + 0.12 }),
      segment([cx, cy], [cx + Math.cos(Math.PI * 0.45) * r * 1.1, cy + Math.sin(Math.PI * 0.45) * r * 1.1], { width: 1e-3, alpha: 0.45, delay: (style.delay ?? 0) + 0.3, dash: [6e-3, 6e-3] }),
      segment([cx - r * 0.9, cy - r * 0.2], [cx + r * 0.2, cy - r * 0.05], { width: 9e-4, alpha: 0.35, delay: (style.delay ?? 0) + 0.35, dash: [4e-3, 6e-3] })
    ],
    nodes: [node([cx, cy], 0.022, (style.delay ?? 0) + 0.3)]
  },
  rays(cx, cy, r * 0.94, r, 30, Math.PI * 0.33, Math.PI * 0.67, { delay: (style.delay ?? 0) + 0.2, alpha: 0.4 })
);
var constellation = (aspect, random, count, region, style = {}) => {
  const [x0, y0, x1, y1] = region;
  const stars = Array.from({ length: count }, () => [(x0 + random() * (x1 - x0)) * aspect, y0 + random() * (y1 - y0)]);
  stars.sort((a, b) => a[0] - b[0]);
  return {
    paths: stars.slice(1).map((star, i) => segment(stars[i], star, { width: 1e-3, alpha: 0.4, ...style, delay: (style.delay ?? 0) + 0.2 + i * 0.06, span: 0.2 })),
    nodes: stars.map((at, i) => node(at, 0.018 + random() * 0.016, (style.delay ?? 0) + i * 0.05, i))
  };
};
var corona = (cx, cy, r, random, style = {}) => ({
  paths: [
    circle(cx, cy, r, { width: 24e-4, alpha: 0.65, ...style }),
    ...Array.from({ length: 40 }, (_, i) => {
      const a = i / 40 * TAU + random() * 0.05;
      const len = r * (0.25 + random() * 0.9);
      return segment([cx + Math.cos(a) * r * 1.05, cy + Math.sin(a) * r * 1.05], [cx + Math.cos(a) * (r + len), cy + Math.sin(a) * (r + len)], {
        width: 8e-4,
        alpha: 0.25 + random() * 0.3,
        delay: (style.delay ?? 0) + 0.2 + i / 40 * 0.3,
        span: 0.15
      });
    })
  ],
  nodes: [node([cx + r * 0.7, cy - r * 0.7], 0.03, (style.delay ?? 0) + 0.5)]
});
var crescent = (cx, cy, r, style = {}) => ({
  paths: [
    path(arcPoints(cx, cy, r, Math.PI * 0.35, Math.PI * 1.65, 60), { width: 2e-3, alpha: 0.6, ...style }),
    path(arcPoints(cx + r * 0.45, cy, r * 0.85, Math.PI * 0.58, Math.PI * 1.42, 60), { width: 12e-4, alpha: 0.4, delay: (style.delay ?? 0) + 0.15 })
  ],
  nodes: []
});
var armillary = (cx, cy, r, style = {}) => ({
  paths: [
    circle(cx, cy, r, { width: 2e-3, alpha: 0.55, ...style }),
    path(ellipsePath(cx, cy, r, r * 0.3, 0), { width: 14e-4, alpha: 0.45, delay: (style.delay ?? 0) + 0.1 }),
    path(ellipsePath(cx, cy, r, r * 0.3, 0.41), { width: 14e-4, alpha: 0.45, delay: (style.delay ?? 0) + 0.15 }),
    path(ellipsePath(cx, cy, r * 0.3, r, 0), { width: 12e-4, alpha: 0.4, delay: (style.delay ?? 0) + 0.2 }),
    segment([cx - Math.sin(0.41) * r * 1.25, cy - Math.cos(0.41) * r * 1.25], [cx + Math.sin(0.41) * r * 1.25, cy + Math.cos(0.41) * r * 1.25], { width: 12e-4, alpha: 0.45, delay: (style.delay ?? 0) + 0.3 })
  ],
  nodes: [node([cx, cy], 0.03, (style.delay ?? 0) + 0.3)]
});
var meteors = (aspect, random, count, style = {}) => {
  const paths = [];
  const nodes = [];
  for (let i = 0; i < count; i += 1) {
    const x = (0.2 + random() * 0.8) * aspect;
    const y = random() * 0.5;
    const len = 0.12 + random() * 0.25;
    const head = [x - len * 0.8, y + len * 0.6];
    paths.push(segment([x, y], head, { width: 12e-4 + random() * 1e-3, alpha: 0.45, ...style, delay: (style.delay ?? 0) + i * 0.08, span: 0.2 }));
    nodes.push(node(head, 0.02, (style.delay ?? 0) + i * 0.08 + 0.2, i));
  }
  return { paths, nodes };
};
var lampHead = (x, y, angle, size, style = {}) => {
  const d = [Math.cos(angle), Math.sin(angle)];
  const n = [-d[1], d[0]];
  const back = [x - d[0] * size, y - d[1] * size];
  const corners = [
    [back[0] + n[0] * size * 0.35, back[1] + n[1] * size * 0.35],
    [x + n[0] * size * 0.6, y + n[1] * size * 0.6],
    [x - n[0] * size * 0.6, y - n[1] * size * 0.6],
    [back[0] - n[0] * size * 0.35, back[1] - n[1] * size * 0.35]
  ];
  return { paths: [path([...corners, corners[0]], { width: 18e-4, alpha: 0.55, span: 0.3, ...style })], nodes: [] };
};
var curtains = (aspect, gap, style = {}) => ({
  paths: [-1, 1].flatMap((side) => Array.from({ length: 6 }, (_, i) => {
    const base = aspect / 2 + side * (gap / 2 + i * 0.05);
    return path(Array.from({ length: 41 }, (_2, k) => {
      const t = k / 40;
      return [base + Math.sin(t * 5 + i) * 8e-3 * side, -0.02 + t * 1.04];
    }), { width: 1e-3 + (5 - i) * 2e-4, alpha: 0.2 + (5 - i) * 0.05, ...style, delay: (style.delay ?? 0) + i * 0.05, span: 0.5 });
  })),
  nodes: []
});
var projector = (x, y, size, style = {}) => ({
  paths: [
    path([[x - size, y - size * 0.3], [x, y - size * 0.3], [x, y + size * 0.3], [x - size, y + size * 0.3], [x - size, y - size * 0.3]], { width: 18e-4, alpha: 0.55, ...style }),
    circle(x - size * 0.75, y - size * 0.65, size * 0.33, { width: 14e-4, alpha: 0.5, delay: (style.delay ?? 0) + 0.1 }),
    circle(x - size * 0.25, y - size * 0.65, size * 0.33, { width: 14e-4, alpha: 0.5, delay: (style.delay ?? 0) + 0.15 }),
    path([[x, y - size * 0.12], [x + size * 0.18, y - size * 0.18], [x + size * 0.18, y + size * 0.18], [x, y + size * 0.12]], { width: 14e-4, alpha: 0.5, delay: (style.delay ?? 0) + 0.2 })
  ],
  nodes: [node([x + size * 0.18, y], 0.024, (style.delay ?? 0) + 0.3)]
});
var horizon = (aspect, y, style = {}) => ({
  paths: [
    segment([0, y], [aspect, y], { width: 14e-4, alpha: 0.4, ...style, span: 0.6 }),
    ...Array.from({ length: 16 }, (_, i) => segment([aspect * (i + 0.5) / 16, y], [aspect * (i + 0.5) / 16, y + 0.012], { width: 8e-4, alpha: 0.3, delay: (style.delay ?? 0) + 0.3 + i * 0.01, span: 0.08 }))
  ],
  nodes: []
});

// folia:src/components/visualizer/lumiere/rigs/base.ts
var TOP = { x: 0.5, y: -0.04 };
var DOWN = Math.PI / 2;
var shaft = (overrides = {}) => ({
  ...TOP,
  angle: DOWN,
  spread: 0.09,
  width: 0.05,
  length: 0.8,
  softness: 0.6,
  intensity: 0.95,
  streaks: 0.6,
  streakFreq: 7,
  streakSpeed: 0.08,
  core: 0.75,
  sway: { amplitude: 0.012, period: 13, phase: 0 },
  ...overrides
});
var fan = (overrides = {}) => ({
  ...TOP,
  angle: DOWN,
  spread: 0.3,
  length: 0.6,
  softness: 0.9,
  intensity: 0.32,
  streaks: 0.85,
  streakFreq: 26,
  streakSpeed: 0.05,
  core: 0.4,
  sway: { amplitude: 0.02, period: 17, phase: 0.3 },
  ...overrides
});
var FOG = { density: 1, tyndallBase: 0.12, scale: 2.4, driftX: 8e-3, driftY: -0.04, warp: 0.9, ambient: 0.03 };
var GLARE = { x: 0.5, y: 0, radius: 0.12, intensity: 0.9, streak: 0.45 };
var MOTES = {
  count: 260,
  sizeMin: 4e-3,
  sizeMax: 0.013,
  driftX: 4e-3,
  driftY: -0.01,
  swirl: 0.02,
  swirlPeriod: 9,
  twinkle: 0.5,
  ambient: 0.015,
  gain: 1.3
};
var FRONT = {
  count: 9,
  sizeMin: 0.05,
  sizeMax: 0.15,
  driftX: 6e-3,
  driftY: -2e-3,
  swirl: 0.012,
  swirlPeriod: 14,
  twinkle: 0.2,
  ambient: 0.02,
  gain: 0.3
};
var STARFALL = { stars: 420, opening: 3.2, rain: 70, rainSpeed: 0.22, rainSpread: 0.35, brightness: 1 };
var standardArt = ({ aspect, random }, haloRadius = 0.3) => mergeSpecs(
  protractorHalo({ cx: aspect * 0.5, cy: 0.03, radius: haloRadius, alpha: 0.55 }),
  viewfinderFrame({ aspect, left: 0.07, top: 0.21, right: 0.93, bottom: 0.8, delay: 0.1, alpha: 0.32 }),
  scatteredSparks({ aspect, count: 16, random, delay: 0.3 })
);
var ellipse = (cx, cy, rx, ry, steps = 96) => arcPoints(0, 0, 1, 0, Math.PI * 2, steps).map(([x, y]) => [cx + x * rx, cy + y * ry]);
var rig = (beams, fog = {}, glare = GLARE, modules = {}) => () => ({
  beams,
  fog: { ...FOG, ...fog },
  glare,
  ...modules
});
var familyOf = (family2, defaults = {}) => (profile) => ({
  family: family2,
  motes: MOTES,
  front: FRONT,
  lineArt: (context) => standardArt(context),
  region: { cx: 0.5, cy: 0.54, w: 0.72, h: 0.5 },
  heroSize: 0.085,
  camera: { push: 0.035, driftX: 0, driftY: -6e-3 },
  ...defaults,
  ...profile
});

// folia:src/components/visualizer/lumiere/rigs/astral.ts
var astral = familyOf("astral", {
  starfall: { ...STARFALL, stars: 620, rain: 20, brightness: 1.1 },
  motes: { ...MOTES, count: 160 },
  // 轨道、星轨、星座、浑天仪的线稿是这一族的主角。
  artGain: 2
});
var sparks = ({ aspect, random }) => scatteredSparks({ aspect, count: 20, random, delay: 0.3 });
var radial = (cx, cy, r, aspect, count, overrides = {}) => Array.from({ length: count }, (_, k) => {
  const angle = k / count * Math.PI * 2 + 0.3;
  return shaft({
    x: cx + Math.cos(angle) * r / aspect,
    y: cy + Math.sin(angle) * r,
    angle,
    spread: 0.14,
    width: 0.04,
    length: 0.35,
    softness: 0.8,
    intensity: 0.7,
    streaks: 0.7,
    streakFreq: 12,
    core: 0.3,
    sway: { amplitude: 0.04, period: 9 + k, phase: k / count },
    ...overrides
  });
});
var astralEclipse = astral({
  kind: "astral-eclipse",
  label: "\u65E5\u98DF",
  mood: "loud",
  light: ({ aspect }) => ({
    beams: radial(0.5, 0.34, 0.13, aspect, 6),
    fog: { density: 0.8, tyndallBase: 0.2, scale: 2.4, driftX: 4e-3, driftY: -0.01, warp: 0.9, ambient: 0.02 },
    glare: { x: 0.5 + 0.13 * Math.cos(-0.8) / aspect, y: 0.34 + 0.13 * Math.sin(-0.8), radius: 0.05, intensity: 1.3, streak: 0.9 }
  }),
  lineArt: ({ aspect, random }) => merge(corona(aspect * 0.5, 0.34, 0.13, random), sparks({ aspect, random })),
  region: { cx: 0.5, cy: 0.7, w: 0.72, h: 0.4 },
  typography: "crossed",
  burst: { mode: "sung", density: 0.35, every: 1, offset: 0, size: 3.6, tint: [1, 0.6, 0.45] },
  decay: { strength: 1.3, delay: 0.7 }
});
var astralOrbit = astral({
  kind: "astral-orbit",
  label: "\u8F68\u9053",
  mood: "quiet",
  light: rig([shaft({ spread: 0.05, intensity: 0.45, reach: 0.4 })], { density: 0.6, ambient: 0.015 }, { x: 0.5, y: 0.42, radius: 0.05, intensity: 1, streak: 0.5 }),
  lineArt: ({ aspect, random }) => merge(orbits(aspect * 0.5, 0.42, [0.12, 0.2, 0.3, 0.42], -0.18, 0.34, random), sparks({ aspect, random })),
  region: { cx: 0.5, cy: 0.74, w: 0.72, h: 0.32 },
  typography: "horizontal",
  decay: { strength: 0.6, delay: 1.6 }
});
var astralTrail = astral({
  kind: "astral-trail",
  label: "\u661F\u8F68",
  mood: "quiet",
  light: rig([shaft({ x: 0.72, spread: 0.04, intensity: 0.35 })], { density: 0.5, ambient: 0.01 }, null),
  lineArt: ({ aspect, random }) => merge(starTrails(aspect * 0.72, 0.12, random, 60, 0.9)),
  region: { cx: 0.36, cy: 0.54, w: 0.44, h: 0.6 },
  typography: "vertical",
  decay: { strength: 0.5, delay: 1.8 }
});
var astralSextant = astral({
  kind: "astral-sextant",
  label: "\u516D\u5206\u4EEA",
  mood: "neutral",
  light: rig([shaft({ x: 0.85, y: -0.05, angle: 2.2, spread: 0.05, width: 0.03, length: 1.4, intensity: 0.9 })], { density: 0.8 }, { ...GLARE, x: 0.85, y: -0.02 }),
  lineArt: ({ aspect, random }) => merge(sextant(aspect * 0.4, 0.14, 0.32), sparks({ aspect, random })),
  region: { cx: 0.52, cy: 0.66, w: 0.72, h: 0.4 },
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var astralConstellation = astral({
  kind: "astral-constellation",
  label: "\u661F\u5EA7",
  mood: "neutral",
  light: rig([shaft({ spread: 0.06, intensity: 0.4 })], { density: 0.6, ambient: 0.015 }, { ...GLARE, intensity: 0.4 }),
  lineArt: ({ aspect, random }) => merge(
    constellation(aspect, random, 8, [0.1, 0.1, 0.9, 0.42]),
    constellation(aspect, random, 5, [0.6, 0.62, 0.95, 0.9], { delay: 0.3 })
  ),
  region: { cx: 0.42, cy: 0.66, w: 0.6, h: 0.4 },
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var astralCorona = astral({
  kind: "astral-corona",
  label: "\u65E5\u5195",
  mood: "loud",
  light: ({ aspect }) => ({
    beams: radial(0.5, 0.12, 0.1, aspect, 6, { length: 0.6, intensity: 0.9 }),
    fog: { density: 1, tyndallBase: 0.15, scale: 2.4, driftX: 4e-3, driftY: -0.02, warp: 0.9, ambient: 0.03 },
    glare: { x: 0.5, y: 0.12, radius: 0.16, intensity: 1.3, streak: 0.7 }
  }),
  lineArt: ({ aspect, random }) => merge(corona(aspect * 0.5, 0.12, 0.1, random), sparks({ aspect, random })),
  region: { cx: 0.5, cy: 0.62, w: 0.72, h: 0.46 },
  typography: "crossed",
  burst: { mode: "sung", density: 0.3, every: 2, offset: 0, size: 3.4, tint: [1, 0.65, 0.4] },
  decay: { strength: 1.3, delay: 0.7 }
});
var astralMoon = astral({
  kind: "astral-moon",
  label: "\u6708\u5149",
  mood: "quiet",
  light: rig(
    [shaft({ x: 0.82, y: 0.12, angle: 2.1, spread: 0.12, width: 0.08, length: 1.4, softness: 0.8, intensity: 0.75, tint: [0.72, 0.82, 1] })],
    { density: 1.2, driftX: -0.01, driftY: 0, ambient: 0.035, warp: 1.3 },
    { x: 0.82, y: 0.12, radius: 0.1, intensity: 0.8, streak: 0.2 }
  ),
  lineArt: ({ aspect, random }) => merge(crescent(aspect * 0.82, 0.12, 0.07), sparks({ aspect, random })),
  region: { cx: 0.38, cy: 0.54, w: 0.5, h: 0.62 },
  typography: "vertical",
  decay: { strength: 0.6, delay: 1.6 }
});
var astralNebula = astral({
  kind: "astral-nebula",
  label: "\u661F\u4E91",
  mood: "neutral",
  light: rig([
    shaft({ x: 0.4, y: 0.45, angle: -0.6, spread: 0.6, width: 0.1, length: 0.8, softness: 1, intensity: 0.5, streaks: 0.6, streakFreq: 3, core: 0.2, spectrum: 0.7, sway: { amplitude: 0.2, period: 20, phase: 0 } }),
    shaft({ x: 0.6, y: 0.45, angle: 2.4, spread: 0.6, width: 0.1, length: 0.8, softness: 1, intensity: 0.4, streaks: 0.6, streakFreq: 3, core: 0.2, spectrum: 0.7, sway: { amplitude: 0.2, period: 23, phase: 0.5 } })
  ], { density: 1.4, ambient: 0.06, warp: 1.6, scale: 1.6, driftX: 6e-3, driftY: 2e-3 }, { x: 0.5, y: 0.45, radius: 0.08, intensity: 0.7, streak: 0.2 }),
  lineArt: sparks,
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var astralArmillary = astral({
  kind: "astral-armillary",
  label: "\u6D51\u5929",
  mood: "neutral",
  light: rig([shaft(), fan({ intensity: 0.2 })]),
  lineArt: ({ aspect, random }) => merge(armillary(aspect * 0.5, 0.42, 0.26), sparks({ aspect, random })),
  region: { cx: 0.5, cy: 0.5, w: 0.5, h: 0.62 },
  typography: "vertical",
  decay: { strength: 1, delay: 1 }
});
var astralMeteor = astral({
  kind: "astral-meteor",
  label: "\u6D41\u661F",
  mood: "loud",
  light: rig([0, 1, 2].map((i) => shaft({
    x: 0.95 - i * 0.2,
    y: -0.02 + i * 0.05,
    angle: 2.5,
    spread: 0.01,
    width: 6e-3,
    length: 0.6,
    intensity: 0.9,
    streaks: 0.2,
    core: 0.8,
    reach: 0.5 + i * 0.1,
    pulse: { amplitude: 0.7, period: 2.2 + i * 0.7, phase: i * 0.3 },
    sway: void 0
  })), { density: 0.7, ambient: 0.015 }, null),
  lineArt: ({ aspect, random }) => merge(meteors(aspect, random, 6), sparks({ aspect, random })),
  typography: "crossed",
  decay: { strength: 1.3, delay: 0.7 },
  starfall: { ...STARFALL, stars: 620, rain: 60, rainSpeed: 0.6, rainSpread: 1.8, brightness: 1.2 }
});
var ASTRAL_PROFILES = [
  astralEclipse,
  astralOrbit,
  astralTrail,
  astralSextant,
  astralConstellation,
  astralCorona,
  astralMoon,
  astralNebula,
  astralArmillary,
  astralMeteor
];

// folia:src/components/visualizer/lumiere/rigs/botany.ts
var botanySprout = {
  kind: "botany-sprout",
  label: "\u840C\u82BD",
  family: "botany",
  mood: "quiet",
  light: () => ({
    beams: [
      {
        x: 0.5,
        y: -0.05,
        angle: Math.PI / 2,
        spread: 0.075,
        width: 0.07,
        length: 1.2,
        softness: 0.7,
        intensity: 0.95,
        streaks: 0.5,
        streakFreq: 6,
        streakSpeed: 0.06,
        core: 0.7,
        sway: { amplitude: 8e-3, period: 15, phase: 0.2 }
      },
      {
        x: 0.5,
        y: -0.05,
        angle: Math.PI / 2,
        spread: 0.26,
        length: 0.75,
        softness: 0.95,
        intensity: 0.42,
        streaks: 0.85,
        streakFreq: 30,
        streakSpeed: 0.04,
        core: 0.3
      }
    ],
    fog: {
      density: 0.9,
      tyndallBase: 0.14,
      scale: 2,
      driftX: -6e-3,
      driftY: -0.03,
      warp: 1.1,
      ambient: 0.025
    },
    glare: { x: 0.5, y: -0.01, radius: 0.1, intensity: 0.9, streak: 0.35 }
  }),
  motes: {
    count: 200,
    sizeMin: 4e-3,
    sizeMax: 0.011,
    driftX: -3e-3,
    driftY: -0.012,
    swirl: 0.018,
    swirlPeriod: 11,
    twinkle: 0.55,
    ambient: 0.012,
    gain: 1.2
  },
  front: {
    count: 6,
    sizeMin: 0.05,
    sizeMax: 0.12,
    driftX: -4e-3,
    driftY: -2e-3,
    swirl: 0.01,
    swirlPeriod: 16,
    twinkle: 0.2,
    ambient: 0.015,
    gain: 0.25
  },
  lineArt: ({ aspect, random }) => mergeSpecs(
    sprout({ cx: aspect * 0.5, baseY: 0.78, size: 0.22, alpha: 1 }),
    protractorHalo({ cx: aspect * 0.5, cy: 0.02, radius: 0.22, alpha: 0.35, delay: 0.2 }),
    viewfinderFrame({ aspect, left: 0.07, top: 0.22, right: 0.93, bottom: 0.8, delay: 0.25, alpha: 0.22 }),
    scatteredSparks({ aspect, count: 12, random, delay: 0.35, region: [0.2, 0.3, 0.8, 0.9] })
  ),
  // 竖排为主：当前行竖在光柱里，像茎一样从叶上长出来。
  region: { cx: 0.5, cy: 0.44, w: 0.72, h: 0.6 },
  heroSize: 0.08,
  // 光柱窄，背景碎片小一点。
  echo: { size: 0.28 },
  typography: "vertical",
  decay: { strength: 0.75, delay: 1.2 },
  starfall: { stars: 300, opening: 3.6, rain: 50, rainSpeed: 0.16, rainSpread: 0.25, brightness: 0.85 },
  camera: { push: 0.03, driftX: 0, driftY: 4e-3 }
};
var botany = familyOf("botany", {
  motes: { ...MOTES, count: 220, driftY: -0.012 },
  // 叶、蕨、花、藤的线稿是这一族的主角。
  artGain: 1.7,
  starfall: { ...STARFALL, rain: 40 }
});
var sparks2 = ({ aspect, random }) => scatteredSparks({ aspect, count: 12, random, delay: 0.3 });
var botanyVeins = botany({
  kind: "botany-veins",
  label: "\u53F6\u8109",
  mood: "neutral",
  light: rig(
    [shaft({ x: 0.15, y: -0.05, angle: 1.1, spread: 0.12, width: 0.12, length: 1.4, intensity: 0.9, streaks: 0.5, streakFreq: 6 })],
    { density: 0.9 },
    { ...GLARE, x: 0.15, y: -0.02, radius: 0.14, intensity: 0.8 }
  ),
  lineArt: (context) => merge(bigLeaf(context.aspect * 0.52, 0.42, 0.62, -0.45), sparks2(context)),
  region: { cx: 0.5, cy: 0.72, w: 0.72, h: 0.36 },
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var botanyCanopy = botany({
  kind: "botany-canopy",
  label: "\u6797\u51A0",
  mood: "loud",
  light: rig([0.25, 0.48, 0.7].map((x, i) => shaft({
    x,
    y: -0.05,
    angle: 1.45 + i * 0.1,
    spread: 0.08,
    width: 0.08,
    length: 1.3,
    softness: 0.6,
    intensity: 0.85,
    streaks: 0.5,
    streakFreq: 6,
    gobo: { pattern: "leaves", frequency: 9, duty: 0.5, drift: 0.14 },
    sway: { amplitude: 0.03, period: 6 + i, phase: i * 0.3 }
  })), { density: 1.1, driftX: 8e-3 }, null),
  lineArt: ({ aspect, random }) => merge(canopy(aspect, random), scatteredSparks({ aspect, count: 16, random, delay: 0.3 })),
  motes: { ...MOTES, count: 300, driftX: 8e-3, driftY: 6e-3, swirl: 0.03 },
  typography: "crossed",
  decay: { strength: 1.2, delay: 0.8 },
  starfall: { ...STARFALL, rain: 90, rainSpread: 1.2 }
});
var botanyFern = botany({
  kind: "botany-fern",
  label: "\u8568\u5377",
  mood: "neutral",
  light: rig([shaft({ x: 0.3, spread: 0.08, intensity: 0.85 }), fan({ x: 0.3, intensity: 0.2 })]),
  lineArt: (context) => merge(fernCurl(context.aspect * 0.28, 0.42, 0.16), sparks2(context)),
  region: { cx: 0.62, cy: 0.5, w: 0.5, h: 0.62 },
  typography: "vertical",
  decay: { strength: 0.8, delay: 1.2 }
});
var botanySeed = botany({
  kind: "botany-seed",
  label: "\u79CD\u5B50",
  mood: "quiet",
  light: rig([shaft({ spread: 0.04, width: 0.02, length: 1.2, intensity: 0.8, core: 0.9 })], { density: 0.7, ambient: 0.02 }, { ...GLARE, intensity: 0.6 }),
  lineArt: ({ aspect, random }) => merge(seedRoots(aspect * 0.5, 0.7, random), scatteredSparks({ aspect, count: 10, random, delay: 0.3 })),
  region: { cx: 0.5, cy: 0.38, w: 0.72, h: 0.4 },
  typography: "horizontal",
  decay: { strength: 0.6, delay: 1.6 }
});
var botanyBloom = botany({
  kind: "botany-bloom",
  label: "\u7EFD\u653E",
  mood: "loud",
  light: rig(Array.from({ length: 6 }, (_, k) => shaft({
    x: 0.5,
    y: 0.42,
    angle: k / 6 * Math.PI * 2 + 0.26,
    spread: 0.12,
    width: 0.01,
    length: 0.6,
    softness: 0.7,
    intensity: 0.55,
    streaks: 0.5,
    streakFreq: 7,
    core: 0.4,
    reach: 0.45,
    sway: { amplitude: 0.05, period: 10, phase: k / 6 }
  })), { density: 0.9 }, { x: 0.5, y: 0.42, radius: 0.1, intensity: 1.2, streak: 0.4 }),
  lineArt: (context) => merge(bloom(context.aspect * 0.5, 0.42, 0.2, 8), sparks2(context)),
  typography: "crossed",
  burst: { mode: "sweep", density: 0.5, every: 3, offset: 1, size: 3, tint: [1, 0.8, 0.7] },
  decay: { strength: 1.2, delay: 0.8 }
});
var botanyVine = botany({
  kind: "botany-vine",
  label: "\u85E4\u65CB",
  mood: "neutral",
  light: rig([shaft({ x: 0.72, spread: 0.07, intensity: 0.9 }), fan({ x: 0.72, intensity: 0.2 })], {}, { ...GLARE, x: 0.72 }),
  lineArt: (context) => merge(vine(context.aspect * 0.72, 1.02, 0.08, 0.05, 4), sparks2(context)),
  region: { cx: 0.36, cy: 0.5, w: 0.5, h: 0.62 },
  typography: "vertical",
  decay: { strength: 1, delay: 1 }
});
var botanyChloro = botany({
  kind: "botany-chloro",
  label: "\u53F6\u7EFF",
  mood: "quiet",
  light: rig(
    [shaft({ spread: 0.2, width: 0.3, softness: 0.9, intensity: 0.6, core: 0.3 })],
    { density: 0.7 },
    null,
    { caustic: { scale: 6, speed: 0.12, inBeam: 0.3, floor: { cx: 0.5, cy: 0.45, rx: 0.2, ry: 0.36, strength: 0.35 } } }
  ),
  lineArt: ({ aspect, random }) => merge(cells(aspect * 0.5, 0.45, 0.36, random, 22), scatteredSparks({ aspect, count: 8, random, delay: 0.3 })),
  region: { cx: 0.5, cy: 0.5, w: 0.5, h: 0.5 },
  typography: "crossed",
  decay: { strength: 0.6, delay: 1.6 }
});
var botanyFormula = botany({
  kind: "botany-formula",
  label: "\u5149\u5408\u5F0F",
  mood: "neutral",
  light: rig([shaft(), fan()]),
  lineArt: (context) => merge(
    molecule(context.aspect * 0.24, 0.3, 0.06),
    molecule(context.aspect * 0.78, 0.74, 0.05, { delay: 0.2 }),
    protractorHalo({ cx: context.aspect * 0.5, cy: 0.03, radius: 0.28, alpha: 0.5 }),
    sparks2(context)
  ),
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var botanyPollen = botany({
  kind: "botany-pollen",
  label: "\u82B1\u7C89",
  mood: "loud",
  light: rig(
    [shaft({ x: 0.2, y: -0.05, angle: 1.15, spread: 0.14, width: 0.16, length: 1.5, intensity: 1, streaks: 0.5 }), fan({ x: 0.2, angle: 1.15, intensity: 0.3 })],
    { density: 1, driftX: 0.012, driftY: -0.01 },
    { ...GLARE, x: 0.2, y: 0 }
  ),
  lineArt: sparks2,
  motes: { count: 360, sizeMin: 6e-3, sizeMax: 0.022, driftX: 0.012, driftY: -6e-3, swirl: 0.04, swirlPeriod: 10, twinkle: 0.4, ambient: 0.02, gain: 1.6 },
  typography: "horizontal",
  decay: { strength: 1.2, delay: 0.8 }
});
var BOTANY_PROFILES = [
  botanySprout,
  botanyVeins,
  botanyCanopy,
  botanyFern,
  botanySeed,
  botanyBloom,
  botanyVine,
  botanyChloro,
  botanyFormula,
  botanyPollen
];

// folia:src/components/visualizer/lumiere/rigs/caustic.ts
var caustic = familyOf("caustic", {
  motes: { ...MOTES, driftY: -4e-3, swirl: 0.03, swirlPeriod: 12 },
  region: { cx: 0.5, cy: 0.46, w: 0.72, h: 0.46 }
});
var sparks3 = (count = 10) => ({ aspect, random }) => scatteredSparks({ aspect, count, random, delay: 0.3 });
var softTop = (overrides = {}) => shaft({
  spread: 0.22,
  width: 0.2,
  length: 1.4,
  softness: 0.8,
  intensity: 0.8,
  streaks: 0.3,
  core: 0.3,
  ...overrides
});
var water = (spec = {}) => ({ caustic: { scale: 2.2, speed: 0.35, inBeam: 0.8, ...spec } });
var causticPool = caustic({
  kind: "caustic-pool",
  label: "\u6C60\u5E95",
  mood: "quiet",
  light: rig(
    [softTop()],
    { density: 0.8, driftY: -0.015, ambient: 0.02 },
    { ...GLARE, intensity: 0.6 },
    water({ floor: { cx: 0.5, cy: 0.82, rx: 0.42, ry: 0.14, strength: 0.7 } })
  ),
  lineArt: ({ aspect, random }) => ({
    paths: [{ points: ellipse(aspect * 0.5, 0.82, aspect * 0.42, 0.14), width: 14e-4, alpha: 0.4, delay: 0.1, span: 0.6 }],
    nodes: sparks3()({ aspect, random }).nodes
  }),
  typography: "horizontal",
  decay: { strength: 0.7, delay: 1.4 }
});
var causticCup = caustic({
  kind: "caustic-cup",
  label: "\u676F\u5F71",
  mood: "neutral",
  light: rig(
    [shaft({ x: -0.05, y: 0.3, angle: 0.35, spread: 0.08, width: 0.18, length: 1.6, softness: 0.5, intensity: 0.9, streaks: 0.3, core: 0.4, sway: void 0 })],
    { density: 0.8 },
    null,
    water({ scale: 3.2, speed: 0.25, inBeam: 0.3, floor: { cx: 0.36, cy: 0.8, rx: 0.14, ry: 0.07, strength: 1.1 } })
  ),
  lineArt: (context) => merge(glassCup(context.aspect * 0.24, 0.52, 0.1, 0.2), sparks3()(context)),
  region: { cx: 0.62, cy: 0.48, w: 0.56, h: 0.64 },
  typography: "vertical",
  decay: { strength: 1, delay: 1 }
});
var causticRipple = caustic({
  kind: "caustic-ripple",
  label: "\u6D9F\u6F2A",
  mood: "neutral",
  light: rig(
    [softTop({ intensity: 0.75 })],
    { density: 0.8 },
    { ...GLARE, intensity: 0.5 },
    water({ scale: 3, speed: 0.5, inBeam: 0.6, floor: { cx: 0.5, cy: 0.8, rx: 0.34, ry: 0.1, strength: 0.5 } })
  ),
  lineArt: (context) => merge(ripples(context.aspect * 0.5, 0.8, 0.34, 5), sparks3()(context)),
  typography: "crossed",
  decay: { strength: 1, delay: 1 }
});
var causticSurface = caustic({
  kind: "caustic-surface",
  label: "\u6C34\u9762",
  mood: "loud",
  light: rig(
    [0.2, 0.42, 0.6, 0.8].map((x, i) => shaft({
      x,
      y: 0.1,
      angle: 1.35 + i * 0.06,
      spread: 0.04,
      width: 0.05,
      length: 1.2,
      softness: 0.6,
      intensity: 0.7,
      streaks: 0.5,
      streakFreq: 6,
      core: 0.5,
      sway: { amplitude: 0.05, period: 6 + i, phase: i * 0.2 }
    })),
    { density: 1.1, driftY: -0.02 },
    null,
    water({ scale: 2.6, speed: 0.6, inBeam: 0.9, floor: { cx: 0.5, cy: 0.06, rx: 0.6, ry: 0.07, strength: 0.9 } })
  ),
  lineArt: (context) => merge(waterline(context.aspect, 0.1, 0.012, 7), sparks3(14)(context)),
  motes: { ...MOTES, count: 300, driftY: -0.02, swirl: 0.03 },
  region: { cx: 0.5, cy: 0.58, w: 0.72, h: 0.46 },
  typography: "horizontal",
  decay: { strength: 1.2, delay: 0.8 }
});
var causticRing = caustic({
  kind: "caustic-ring",
  label: "\u6212\u5149",
  mood: "quiet",
  light: rig(
    [softTop({ spread: 0.14, width: 0.1, intensity: 0.7 })],
    { density: 0.7 },
    { ...GLARE, intensity: 0.5 },
    water({ scale: 4, speed: 0.2, inBeam: 0.2, floor: { cx: 0.5, cy: 0.5, rx: 0.2, ry: 0.36, strength: 0.6 } })
  ),
  lineArt: (context) => merge(
    { paths: [circle(context.aspect * 0.5, 0.5, 0.36, { width: 24e-4, alpha: 0.6 }), circle(context.aspect * 0.5, 0.5, 0.32, { width: 9e-4, alpha: 0.3, delay: 0.1 })], nodes: [] },
    sparks3()(context)
  ),
  region: { cx: 0.5, cy: 0.5, w: 0.4, h: 0.62 },
  typography: "vertical",
  decay: { strength: 0.6, delay: 1.6 }
});
var causticBurn = caustic({
  kind: "caustic-burn",
  label: "\u805A\u70B9",
  mood: "loud",
  light: rig([
    shaft({ x: 0.5, y: 0.2, angle: Math.PI / 2, spread: -0.22, width: 0.2, length: 1.4, softness: 0.5, intensity: 1.2, streaks: 0.3, streakFreq: 5, core: 0.6, sway: { amplitude: 0.02, period: 9, phase: 0 } }),
    shaft({ x: 0.5, y: -0.1, angle: Math.PI / 2, spread: 0.03, width: 0.22, length: 1, intensity: 0.4, streaks: 0.4, reach: 0.3, sway: void 0 })
  ], { density: 1 }, { x: 0.5, y: 0.65, radius: 0.05, intensity: 1.1, streak: 0.8 }),
  lineArt: (context) => merge(magnifier(context.aspect * 0.5, 0.2, 0.1), sparks3(12)(context)),
  region: { cx: 0.5, cy: 0.66, w: 0.72, h: 0.4 },
  typography: "crossed",
  burst: { mode: "sung", density: 0.35, every: 1, offset: 0, size: 3.6, tint: [1, 0.7, 0.45] },
  decay: { strength: 1.3, delay: 0.7 }
});
var causticShimmer = caustic({
  kind: "caustic-shimmer",
  label: "\u7CBC\u7CBC",
  mood: "neutral",
  light: rig(
    [shaft({
      x: -0.05,
      y: 0.5,
      angle: 0.02,
      spread: 0.06,
      width: 0.5,
      length: 2.4,
      softness: 0.4,
      intensity: 0.8,
      streaks: 0.2,
      core: 0.2,
      gobo: { pattern: "blinds", frequency: 18, duty: 0.35, drift: 0.3 },
      sway: void 0
    })],
    { density: 0.8 },
    null,
    water({ scale: 1.4, speed: 0.8, inBeam: 0.6 })
  ),
  lineArt: (context) => merge(waterline(context.aspect, 0.86, 8e-3, 9), sparks3()(context)),
  region: { cx: 0.5, cy: 0.5, w: 0.72, h: 0.5 },
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var causticCrystal = caustic({
  kind: "caustic-crystal",
  label: "\u6676\u5F71",
  mood: "neutral",
  light: rig(
    [0, 1, 2, 3, 4].map((k) => shaft({
      x: 0.5,
      y: 0.26,
      angle: Math.PI / 2 + (k - 2) * 0.45,
      spread: 0.05,
      width: 0.01,
      length: 0.8,
      softness: 0.5,
      intensity: 0.6,
      streaks: 0.3,
      core: 0.4,
      spectrum: 0.7,
      sway: { amplitude: 0.05, period: 12, phase: k * 0.15 }
    })),
    { density: 0.9 },
    { ...GLARE, x: 0.5, y: 0.26, radius: 0.07, intensity: 1, streak: 0.5 },
    water({ scale: 3.4, speed: 0.2, inBeam: 0.4, floor: { cx: 0.5, cy: 0.8, rx: 0.3, ry: 0.09, strength: 0.5 } })
  ),
  lineArt: (context) => merge(crystal(context.aspect * 0.5, 0.26, 0.05), sparks3(14)(context)),
  region: { cx: 0.5, cy: 0.58, w: 0.72, h: 0.44 },
  typography: "crossed",
  decay: { strength: 1, delay: 1 }
});
var causticDrift = caustic({
  kind: "caustic-drift",
  label: "\u6F02\u6D41",
  mood: "quiet",
  light: rig(
    [softTop({ spread: 0.4, width: 0.4, intensity: 1, softness: 0.95 })],
    { density: 0.8, driftX: 4e-3, driftY: 0, ambient: 0.03 },
    { ...GLARE, intensity: 0.5 },
    water({ scale: 1, speed: 0.08, inBeam: 0.8, floor: { cx: 0.5, cy: 0.5, rx: 0.5, ry: 0.4, strength: 0.4 } })
  ),
  lineArt: sparks3(8),
  region: { cx: 0.5, cy: 0.5, w: 0.72, h: 0.62 },
  typography: "vertical",
  decay: { strength: 0.5, delay: 1.8 }
});
var causticStorm = caustic({
  kind: "caustic-storm",
  label: "\u9AA4\u5149",
  mood: "loud",
  light: rig(
    [softTop({ intensity: 1, pulse: { amplitude: 0.35, period: 0.9, phase: 0 } })],
    { density: 1.1 },
    { ...GLARE, intensity: 0.8 },
    water({ scale: 3, speed: 1.3, inBeam: 1, floor: { cx: 0.5, cy: 0.82, rx: 0.5, ry: 0.14, strength: 0.8 } })
  ),
  lineArt: (context) => merge(ripples(context.aspect * 0.5, 0.82, 0.5, 4), sparks3(14)(context)),
  typography: "horizontal",
  decay: { strength: 1.3, delay: 0.7 }
});
var CAUSTIC_PROFILES = [
  causticPool,
  causticCup,
  causticRipple,
  causticSurface,
  causticRing,
  causticBurn,
  causticShimmer,
  causticCrystal,
  causticDrift,
  causticStorm
];

// folia:src/components/visualizer/lumiere/rigs/lattice.ts
var lattice = familyOf("lattice", {
  region: { cx: 0.56, cy: 0.58, w: 0.66, h: 0.5 },
  motes: { ...MOTES, driftX: 8e-3, driftY: -6e-3 }
});
var windowBeam = (overrides = {}) => shaft({
  x: 0.1,
  y: 0.06,
  angle: 0.62,
  spread: 0.1,
  width: 0.34,
  length: 1.3,
  softness: 0.35,
  intensity: 1,
  streaks: 0.25,
  streakFreq: 4,
  core: 0.3,
  sway: { amplitude: 0.01, period: 17, phase: 0 },
  ...overrides
});
var sparks4 = (region) => ({ aspect, random }) => scatteredSparks({ aspect, count: 14, random, delay: 0.3, region: region ?? [0.3, 0.3, 0.95, 0.9] });
var latticeBlinds = lattice({
  kind: "lattice-blinds",
  label: "\u767E\u53F6",
  mood: "neutral",
  light: rig(
    [windowBeam({ gobo: { pattern: "blinds", frequency: 13, duty: 0.52, drift: 0.02 } })],
    { driftX: 0.012, driftY: -0.02 },
    { ...GLARE, x: 0.1, y: 0.06, radius: 0.16, intensity: 0.8 }
  ),
  lineArt: (context) => mergeSpecs(
    blindsWindow({ x: context.aspect * 0.03, y: 0.02, w: context.aspect * 0.16, h: 0.26, slats: 9, alpha: 0.5 }),
    sparks4()(context)
  ),
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var latticeCross = lattice({
  kind: "lattice-cross",
  label: "\u5341\u5B57\u7A97",
  mood: "quiet",
  light: rig(
    [windowBeam({ x: 0.9, angle: Math.PI - 0.7, width: 0.3, intensity: 0.9, gobo: { pattern: "cross", frequency: 0, duty: 0.16, drift: 0 } })],
    { driftX: -8e-3 },
    { ...GLARE, x: 0.9, y: 0.06, radius: 0.14, intensity: 0.7 }
  ),
  lineArt: (context) => mergeSpecs(
    crossWindow(context.aspect * 0.8, 0.01, context.aspect * 0.16, 0.26),
    sparks4([0.05, 0.3, 0.7, 0.9])(context)
  ),
  region: { cx: 0.4, cy: 0.52, w: 0.6, h: 0.62 },
  typography: "vertical",
  decay: { strength: 0.7, delay: 1.4 }
});
var latticeArch = lattice({
  kind: "lattice-arch",
  label: "\u62F1\u7A97",
  mood: "loud",
  light: rig([
    windowBeam({ x: 0.14, y: -0.02, angle: 0.95, width: 0.14, spread: 0.06, length: 1.6, intensity: 1.3, streaks: 0.55, streakFreq: 8, core: 0.6 }),
    windowBeam({ x: 0.14, y: -0.02, angle: 0.95, width: 0.3, spread: 0.2, length: 0.9, softness: 0.9, intensity: 0.3, streaks: 0.8, streakFreq: 22 })
  ], { density: 1.1 }, { ...GLARE, x: 0.14, y: 0, radius: 0.18, intensity: 1.1, streak: 0.6 }),
  lineArt: (context) => mergeSpecs(
    archWindow(context.aspect * 0.08, -0.06, context.aspect * 0.12, 0.32),
    sparks4()(context)
  ),
  typography: "crossed",
  decay: { strength: 1.2, delay: 0.8 },
  starfall: { ...STARFALL, rain: 90, rainSpread: 0.8 }
});
var latticeRose = lattice({
  kind: "lattice-rose",
  label: "\u73AB\u7470\u7A97",
  mood: "loud",
  light: rig([-2, -1, 0, 1, 2, 3].map((k) => shaft({
    y: 0.08,
    angle: Math.PI / 2 + (k - 0.5) * 0.2,
    spread: 0.035,
    width: 0.03,
    length: 1,
    intensity: 0.65 - Math.abs(k - 0.5) * 0.06,
    streaks: 0.4,
    streakFreq: 5,
    sway: { amplitude: 0.015, period: 13, phase: k * 0.1 }
  })), {}, { ...GLARE, y: 0.08, radius: 0.16, intensity: 1.1, streak: 0.5 }),
  lineArt: ({ aspect, random }) => mergeSpecs(
    roseWindow(aspect * 0.5, 0.08, 0.12),
    scatteredSparks({ aspect, count: 16, random, delay: 0.3 })
  ),
  region: { cx: 0.5, cy: 0.6, w: 0.72, h: 0.46 },
  typography: "horizontal",
  decay: { strength: 1.2, delay: 0.8 },
  starfall: STARFALL
});
var latticeSlit = lattice({
  kind: "lattice-slit",
  label: "\u95E8\u7F1D",
  mood: "quiet",
  light: rig(
    [shaft({ x: 0.1, y: 0.42, angle: 0.06, spread: 0.02, width: 0.012, length: 2.4, intensity: 1, streaks: 0.3, streakFreq: 3, core: 0.8, sway: { amplitude: 0.01, period: 15, phase: 0 } })],
    { density: 0.8, ambient: 0.015 },
    { ...GLARE, x: 0.1, y: 0.42, radius: 0.08, intensity: 0.8, streak: 0.9 }
  ),
  lineArt: ({ aspect, random }) => mergeSpecs(
    doorSlit(aspect * 0.1, 0.08, 0.86, 0.012),
    scatteredSparks({ aspect, count: 10, random, delay: 0.3, region: [0.2, 0.2, 0.95, 0.9] })
  ),
  region: { cx: 0.55, cy: 0.5, w: 0.6, h: 0.64 },
  typography: "vertical",
  decay: { strength: 0.6, delay: 1.6 }
});
var latticeShoji = lattice({
  kind: "lattice-shoji",
  label: "\u969C\u5B50",
  mood: "quiet",
  light: rig([windowBeam({
    x: 0.12,
    y: 0.1,
    angle: 0.4,
    width: 0.5,
    spread: 0.18,
    softness: 0.95,
    intensity: 0.7,
    streaks: 0.1,
    core: 0.2,
    gobo: { pattern: "blinds", frequency: 10, duty: 0.86, drift: 0 }
  })], { density: 0.7, tyndallBase: 0.25 }, null),
  lineArt: ({ aspect, random }) => mergeSpecs(
    gridPanel(aspect * 0.02, 0.06, aspect * 0.18, 0.4, 3, 5),
    scatteredSparks({ aspect, count: 10, random, delay: 0.3 })
  ),
  typography: "horizontal",
  decay: { strength: 0.6, delay: 1.6 }
});
var latticeGrille = lattice({
  kind: "lattice-grille",
  label: "\u683C\u6805",
  mood: "neutral",
  light: rig(
    [windowBeam({ width: 0.4, spread: 0.12, intensity: 1, gobo: { pattern: "lattice", frequency: 9, duty: 0.62, drift: 0.04 } })],
    { driftX: 0.01 },
    { ...GLARE, x: 0.1, y: 0.06, radius: 0.14, intensity: 0.7 }
  ),
  lineArt: (context) => mergeSpecs(
    gridPanel(context.aspect * 0.02, 0.02, context.aspect * 0.16, 0.26, 4, 4, true),
    sparks4()(context)
  ),
  typography: "crossed",
  decay: { strength: 1, delay: 1 }
});
var latticeSweep = lattice({
  kind: "lattice-sweep",
  label: "\u626B\u7A97",
  mood: "neutral",
  light: rig(
    [windowBeam({ angle: 0.75, width: 0.3, intensity: 1, sway: { amplitude: 0.32, period: 10, phase: 0 }, gobo: { pattern: "blinds", frequency: 11, duty: 0.55, drift: 0.05 } })],
    { driftX: 0.01 },
    { ...GLARE, x: 0.1, y: 0.06, radius: 0.14, intensity: 0.7 }
  ),
  lineArt: (context) => mergeSpecs(
    blindsWindow({ x: context.aspect * 0.03, y: 0.02, w: context.aspect * 0.16, h: 0.26, slats: 8, alpha: 0.45 }),
    sparks4()(context)
  ),
  typography: "horizontal",
  decay: { strength: 1, delay: 1 },
  camera: { push: 0.02, driftX: 0.012, driftY: 0 }
});
var latticeKomorebi = lattice({
  kind: "lattice-komorebi",
  label: "\u53F6\u9699",
  mood: "quiet",
  light: rig([
    shaft({
      x: 0.35,
      y: -0.05,
      angle: 1.35,
      spread: 0.2,
      width: 0.2,
      length: 1.3,
      softness: 0.7,
      intensity: 1,
      streaks: 0.2,
      core: 0.3,
      gobo: { pattern: "leaves", frequency: 7, duty: 0.52, drift: 0.12 },
      sway: { amplitude: 0.03, period: 7, phase: 0 }
    }),
    shaft({
      x: 0.72,
      y: -0.05,
      angle: 1.8,
      spread: 0.14,
      width: 0.12,
      length: 1.1,
      softness: 0.7,
      intensity: 0.7,
      streaks: 0.2,
      core: 0.3,
      gobo: { pattern: "leaves", frequency: 8, duty: 0.55, drift: 0.1 },
      sway: { amplitude: 0.03, period: 8, phase: 0.4 }
    })
  ], { density: 0.9, driftX: 0.01 }, null),
  lineArt: ({ aspect, random }) => merge(canopy(aspect, random), scatteredSparks({ aspect, count: 12, random, delay: 0.3 })),
  motes: { ...MOTES, count: 220, driftX: 0.01, driftY: 4e-3, swirl: 0.03 },
  region: { cx: 0.5, cy: 0.54, w: 0.72, h: 0.6 },
  typography: "vertical",
  decay: { strength: 0.8, delay: 1.2 }
});
var latticeNave = lattice({
  kind: "lattice-nave",
  label: "\u6BBF\u5802",
  mood: "loud",
  light: rig([0.12, 0.34, 0.56, 0.78].map((x, i) => windowBeam({
    x,
    y: -0.02,
    angle: 1.1,
    width: 0.06,
    spread: 0.05,
    length: 1.5,
    softness: 0.5,
    intensity: 0.75,
    streaks: 0.5,
    streakFreq: 6,
    core: 0.5,
    sway: { amplitude: 8e-3, period: 19, phase: i * 0.2 }
  })), { density: 1.2, driftX: 6e-3, driftY: -0.03 }, { ...GLARE, x: 0.45, y: 0, radius: 0.25, intensity: 0.6, streak: 0.3 }),
  lineArt: ({ aspect, random }) => mergeSpecs(
    tallWindows(aspect * 0.05, aspect * 0.95, -0.08, 0.26, 4),
    scatteredSparks({ aspect, count: 18, random, delay: 0.3 })
  ),
  typography: "crossed",
  decay: { strength: 1.2, delay: 0.8 },
  starfall: { ...STARFALL, rain: 80, rainSpread: 1.2 }
});
var LATTICE_PROFILES = [
  latticeBlinds,
  latticeCross,
  latticeArch,
  latticeRose,
  latticeSlit,
  latticeShoji,
  latticeGrille,
  latticeSweep,
  latticeKomorebi,
  latticeNave
];

// folia:src/components/visualizer/lumiere/rigs/motes.ts
var motesFamily = familyOf("motes", {
  starfall: { ...STARFALL, rain: 30 },
  lineArt: ({ aspect, random }) => scatteredSparks({ aspect, count: 10, random, delay: 0.3 })
});
var particles = (overrides) => ({ ...MOTES, ...overrides });
var motesDust = motesFamily({
  kind: "motes-dust",
  label: "\u6D6E\u5C18",
  mood: "quiet",
  light: rig([shaft({ x: 0.15, y: -0.05, angle: 1.05, spread: 0.1, width: 0.1, length: 1.5, intensity: 0.8, streaks: 0.4 })], { density: 0.8, ambient: 0.015 }, null),
  motes: particles({ count: 420, sizeMin: 3e-3, sizeMax: 0.012, driftX: 2e-3, driftY: -4e-3, swirl: 0.035, swirlPeriod: 14, gain: 1.6 }),
  typography: "horizontal",
  decay: { strength: 0.7, delay: 1.4 }
});
var motesFirefly = motesFamily({
  kind: "motes-firefly",
  label: "\u8424\u706B",
  mood: "quiet",
  light: rig([shaft({ spread: 0.05, intensity: 0.15 })], { density: 0.6, ambient: 0.02 }, null),
  motes: particles({ count: 90, sizeMin: 8e-3, sizeMax: 0.022, driftX: 3e-3, driftY: -3e-3, swirl: 0.06, swirlPeriod: 11, twinkle: 0.9, ambient: 0.55, gain: 0.8 }),
  front: { ...FRONT, count: 14, ambient: 0.12, twinkle: 0.7 },
  region: { cx: 0.5, cy: 0.5, w: 0.5, h: 0.62 },
  typography: "vertical",
  decay: { strength: 0.6, delay: 1.6 }
});
var motesSmoke = motesFamily({
  kind: "motes-smoke",
  label: "\u70DF\u7F15",
  mood: "neutral",
  light: rig(
    [shaft({ x: -0.05, y: 0.55, angle: -0.08, spread: 0.18, width: 0.3, length: 1.6, softness: 0.7, intensity: 0.42, streaks: 0.2, core: 0.3, sway: void 0 })],
    { density: 1.5, tyndallBase: 0.05, scale: 1.8, warp: 1.8, driftX: 4e-3, driftY: -0.06, ambient: 0.05 },
    null
  ),
  motes: particles({ count: 140 }),
  typography: "crossed",
  decay: { strength: 1, delay: 1 }
});
var motesEmbers = motesFamily({
  kind: "motes-embers",
  label: "\u98DE\u70EC",
  mood: "loud",
  light: rig([shaft({
    x: 0.5,
    y: 1.05,
    angle: -Math.PI / 2,
    spread: 0.35,
    width: 0.3,
    length: 0.6,
    softness: 0.9,
    intensity: 0.8,
    streaks: 0.6,
    streakFreq: 8,
    core: 0.3,
    tint: [1, 0.55, 0.3],
    pulse: { amplitude: 0.2, period: 1.3, phase: 0 },
    sway: void 0
  })], { density: 1.1, driftY: -0.05 }, null),
  motes: particles({ count: 380, sizeMin: 3e-3, sizeMax: 0.01, driftX: 4e-3, driftY: -0.07, swirl: 0.03, swirlPeriod: 5, twinkle: 0.8, ambient: 0.1, gain: 1.8 }),
  region: { cx: 0.5, cy: 0.44, w: 0.72, h: 0.46 },
  typography: "horizontal",
  decay: { strength: 1.4, delay: 0.6 }
});
var motesSnow = motesFamily({
  kind: "motes-snow",
  label: "\u5149\u96EA",
  mood: "quiet",
  light: rig([shaft({ spread: 0.2, width: 0.2, softness: 0.9, intensity: 0.5, core: 0.3 })], { density: 0.8, driftY: 0.01 }, null),
  motes: particles({ count: 460, sizeMin: 3e-3, sizeMax: 0.012, driftX: 3e-3, driftY: 0.035, swirl: 0.02, swirlPeriod: 8, twinkle: 0.3, ambient: 0.15, gain: 1 }),
  region: { cx: 0.5, cy: 0.5, w: 0.5, h: 0.62 },
  typography: "vertical",
  decay: { strength: 0.6, delay: 1.6 },
  starfall: { ...STARFALL, rain: 60, rainSpeed: 0.12, rainSpread: 1.8, brightness: 0.7 }
});
var motesBokeh = motesFamily({
  kind: "motes-bokeh",
  label: "\u6563\u666F",
  mood: "neutral",
  light: rig([shaft({ intensity: 0.6 })], { density: 0.8 }, null),
  motes: particles({ count: 120 }),
  front: { ...FRONT, count: 34, sizeMin: 0.06, sizeMax: 0.2, ambient: 0.1, gain: 0.5, twinkle: 0.3, driftX: 8e-3 },
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var motesMist = motesFamily({
  kind: "motes-mist",
  label: "\u6668\u96FE",
  mood: "quiet",
  // 雾后的光：光束与眩光都压低，眩光不拉横丝（原来亮得发白，一条横线贯穿画面）。
  light: rig(
    [shaft({ x: 0.7, y: 0.62, angle: -2.8, spread: 0.5, width: 0.3, length: 1.2, softness: 1, intensity: 0.55, streaks: 0.3, core: 0.2, sway: void 0 })],
    { density: 1.5, tyndallBase: 0.1, scale: 1.2, warp: 0.6, driftX: 0.02, driftY: 0, ambient: 0.05 },
    { x: 0.7, y: 0.62, radius: 0.16, intensity: 0.5, streak: 0.08 }
  ),
  lineArt: ({ aspect, random }) => merge(horizon(aspect, 0.64), scatteredSparks({ aspect, count: 8, random, delay: 0.3, region: [0.05, 0.05, 0.95, 0.55] })),
  motes: particles({ count: 120, driftX: 0.01 }),
  region: { cx: 0.36, cy: 0.42, w: 0.44, h: 0.5 },
  typography: "vertical",
  decay: { strength: 0.6, delay: 1.6 }
});
var motesSwarm = motesFamily({
  kind: "motes-swarm",
  label: "\u5149\u7FA4",
  mood: "loud",
  light: rig([shaft({ intensity: 0.8 }), shaft({ spread: 0.3, length: 0.6, softness: 0.9, intensity: 0.25, streaks: 0.8, streakFreq: 24 })]),
  motes: particles({ count: 460, sizeMin: 3e-3, sizeMax: 0.012, driftX: 0, driftY: 0, swirl: 0.14, swirlPeriod: 6, twinkle: 0.6, ambient: 0.08, gain: 1.6 }),
  typography: "crossed",
  decay: { strength: 1.3, delay: 0.7 }
});
var motesDissolve = motesFamily({
  kind: "motes-dissolve",
  label: "\u5316\u5C18",
  mood: "neutral",
  light: rig([shaft({ intensity: 0.7 })]),
  motes: particles({ count: 380, driftY: -0.02, swirl: 0.04, gain: 1.5 }),
  typography: "crossed",
  decay: { strength: 2.2, delay: 0.3 }
});
var motesAurora = motesFamily({
  kind: "motes-aurora",
  label: "\u6781\u5149",
  mood: "loud",
  light: rig([0.2, 0.4, 0.6, 0.8].map((x, i) => shaft({
    x,
    y: -0.1,
    angle: Math.PI / 2 + 0.1,
    spread: 0.06,
    width: 0.16,
    length: 0.7,
    softness: 0.8,
    intensity: 0.7,
    streaks: 0.9,
    streakFreq: 30,
    streakSpeed: 0.3,
    core: 0.2,
    spectrum: 0.5,
    tint: [0.6, 1, 0.8],
    sway: { amplitude: 0.12, period: 8 + i * 1.7, phase: i * 0.2 }
  })), { density: 0.9, ambient: 0.03 }, null),
  region: { cx: 0.5, cy: 0.62, w: 0.72, h: 0.4 },
  typography: "horizontal",
  decay: { strength: 1.2, delay: 0.8 },
  starfall: { ...STARFALL, stars: 560, rain: 20 }
});
var MOTES_PROFILES = [
  motesDust,
  motesFirefly,
  motesSmoke,
  motesEmbers,
  motesSnow,
  motesBokeh,
  motesMist,
  motesSwarm,
  motesDissolve,
  motesAurora
];

// folia:src/components/visualizer/lumiere/rigs/optics.ts
var optics = familyOf("optics", {
  region: { cx: 0.5, cy: 0.74, w: 0.72, h: 0.3 },
  heroSize: 0.075,
  motes: { ...MOTES, count: 180 }
});
var ray = (aspect, a, b, overrides = {}, open = false) => {
  const dx = (b[0] - a[0]) * aspect;
  const dy = b[1] - a[1];
  return {
    x: a[0],
    y: a[1],
    angle: Math.atan2(dy, dx),
    spread: 4e-3,
    width: 8e-3,
    length: 3,
    softness: 0.6,
    intensity: 0.9,
    streaks: 0.1,
    streakFreq: 3,
    streakSpeed: 0.05,
    core: 0.8,
    ...open ? {} : { reach: Math.hypot(dx, dy) + 0.02 },
    ...overrides
  };
};
var rayArt = (aspect, points, delay = 0.2) => rayPath(points.map(([x, y]) => [x * aspect, y]), { delay });
var opticsRig = (beams, glare = null) => ({
  beams,
  fog: { ...FOG, density: 0.9, tyndallBase: 0.2, ambient: 0.02 },
  glare
});
var sparks5 = ({ aspect, random }) => scatteredSparks({ aspect, count: 10, random, delay: 0.3, region: [0.05, 0.05, 0.95, 0.6] });
var AXIS = 0.4;
var opticsConvex = optics({
  kind: "optics-convex",
  label: "\u4F1A\u805A",
  mood: "neutral",
  light: ({ aspect }) => opticsRig([0.3, 0.4, 0.5].flatMap((y) => [
    ray(aspect, [-0.02, y], [0.42, y]),
    ray(aspect, [0.42, y], [0.7, AXIS], {}, true)
  ]), { x: 0.7, y: AXIS, radius: 0.05, intensity: 0.9, streak: 0.6 }),
  lineArt: (context) => merge(
    lens(context.aspect * 0.42, AXIS, 0.3, true, context.aspect),
    ...[0.3, 0.4, 0.5].map((y, i) => rayArt(context.aspect, [[0.02, y], [0.42, y], [0.7, AXIS], [0.92, AXIS + (AXIS - y) * 0.8]], 0.2 + i * 0.08)),
    focusMark(context.aspect * 0.7, AXIS, { delay: 0.5 }),
    sparks5(context)
  ),
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var opticsConcave = optics({
  kind: "optics-concave",
  label: "\u53D1\u6563",
  mood: "quiet",
  light: ({ aspect }) => opticsRig([0.32, 0.4, 0.48].flatMap((y) => [
    ray(aspect, [-0.02, y], [0.42, y], { intensity: 0.7 }),
    ray(aspect, [0.42, y], [0.42 + (0.42 - 0.26), y + (y - AXIS) * 1.6], { intensity: 0.7, spread: 0.01 }, true)
  ])),
  lineArt: (context) => merge(
    lens(context.aspect * 0.42, AXIS, 0.28, false, context.aspect),
    ...[0.32, 0.48].map((y, i) => merge(
      rayArt(context.aspect, [[0.02, y], [0.42, y], [0.62, y + (y - AXIS) * 2.2]], 0.2 + i * 0.1),
      { paths: [segment([context.aspect * 0.42, y], [context.aspect * 0.26, AXIS], { width: 9e-4, alpha: 0.35, delay: 0.5, dash: [5e-3, 6e-3] })], nodes: [] }
    )),
    focusMark(context.aspect * 0.26, AXIS, { delay: 0.6 }),
    sparks5(context)
  ),
  region: { cx: 0.72, cy: 0.56, w: 0.4, h: 0.72 },
  typography: "vertical",
  decay: { strength: 0.7, delay: 1.4 }
});
var opticsMirror = optics({
  kind: "optics-mirror",
  label: "\u53CD\u5C04",
  mood: "quiet",
  light: ({ aspect }) => opticsRig([
    ray(aspect, [0.12, 0.08], [0.5, 0.6], { width: 0.02, intensity: 1 }),
    ray(aspect, [0.5, 0.6], [0.88, 0.08], { width: 0.02, intensity: 0.8 }, true)
  ], { x: 0.5, y: 0.6, radius: 0.05, intensity: 0.8, streak: 0.7 }),
  lineArt: (context) => merge(
    mirror(context.aspect * 0.5, 0.6, 0.6, 0),
    rayArt(context.aspect, [[0.12, 0.08], [0.5, 0.6], [0.88, 0.08]]),
    sparks5(context)
  ),
  region: { cx: 0.5, cy: 0.34, w: 0.5, h: 0.36 },
  heroSize: 0.07,
  typography: "crossed",
  decay: { strength: 0.7, delay: 1.4 }
});
var opticsRefract = optics({
  kind: "optics-refract",
  label: "\u6298\u5C04",
  mood: "neutral",
  light: ({ aspect }) => opticsRig([
    ray(aspect, [0.18, 0.05], [0.46, 0.5], { width: 0.02, intensity: 1 }),
    ray(aspect, [0.46, 0.5], [0.58, 1.05], { width: 0.02, intensity: 0.8 }, true),
    ray(aspect, [0.46, 0.5], [0.74, 0.05], { width: 0.01, intensity: 0.3 }, true)
  ], { x: 0.46, y: 0.5, radius: 0.05, intensity: 0.8, streak: 0.8 }),
  lineArt: (context) => merge(
    interfaceLine(context.aspect, 0.5),
    rayArt(context.aspect, [[0.18, 0.05], [0.46, 0.5], [0.58, 0.98]]),
    { paths: [segment([context.aspect * 0.46, 0.18], [context.aspect * 0.46, 0.82], { width: 9e-4, alpha: 0.35, delay: 0.4, dash: [6e-3, 6e-3] })], nodes: [] },
    sparks5(context)
  ),
  region: { cx: 0.72, cy: 0.3, w: 0.44, h: 0.3 },
  heroSize: 0.07,
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var opticsBench = optics({
  kind: "optics-bench",
  label: "\u5149\u5177\u5EA7",
  mood: "neutral",
  light: ({ aspect }) => opticsRig([
    ray(aspect, [-0.02, AXIS], [0.3, AXIS], { width: 0.05, spread: 0.01, intensity: 0.8 }),
    { ...ray(aspect, [0.3, AXIS], [0.5, AXIS], { width: 0.05, intensity: 0.9 }), spread: -0.06 },
    { ...ray(aspect, [0.5, AXIS], [0.7, AXIS], { width: 0.02, intensity: 0.9 }), spread: 0.06 },
    ray(aspect, [0.7, AXIS], [1.02, AXIS], { width: 0.05, intensity: 0.7 }, true)
  ], { x: 0.5, y: AXIS, radius: 0.04, intensity: 0.7, streak: 0.6 }),
  lineArt: (context) => merge(
    ...[0.3, 0.5, 0.7].map((x, i) => lens(context.aspect * x, AXIS, 0.16 + i % 2 * 0.04, i !== 1, context.aspect, { delay: i * 0.1 })),
    ruler(context.aspect * 0.06, context.aspect * 0.94, 0.58, 40, { delay: 0.3 }),
    sparks5(context)
  ),
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var opticsPeriscope = optics({
  kind: "optics-periscope",
  label: "\u6F5C\u671B",
  mood: "neutral",
  light: ({ aspect }) => opticsRig([
    ray(aspect, [1.02, 0.14], [0.3, 0.14], { width: 0.02 }),
    ray(aspect, [0.3, 0.14], [0.3, 0.84], { width: 0.02 }),
    ray(aspect, [0.3, 0.84], [1.02, 0.84], { width: 0.02, intensity: 0.8 }, true)
  ], { x: 0.3, y: 0.14, radius: 0.04, intensity: 0.7, streak: 0.4 }),
  lineArt: (context) => merge(
    mirror(context.aspect * 0.3, 0.14, 0.14, Math.PI / 4),
    mirror(context.aspect * 0.3, 0.84, 0.14, Math.PI / 4, { delay: 0.1 }),
    rayArt(context.aspect, [[0.98, 0.14], [0.3, 0.14], [0.3, 0.84], [0.98, 0.84]]),
    sparks5(context)
  ),
  region: { cx: 0.62, cy: 0.49, w: 0.4, h: 0.5 },
  typography: "vertical",
  decay: { strength: 0.8, delay: 1.2 }
});
var opticsFiber = optics({
  kind: "optics-fiber",
  label: "\u5149\u7EA4",
  mood: "loud",
  light: () => opticsRig([
    {
      x: 0.84,
      y: 0.2,
      angle: -0.5,
      spread: 0.3,
      width: 0.02,
      length: 0.9,
      softness: 0.6,
      intensity: 1.2,
      streaks: 0.5,
      streakFreq: 9,
      streakSpeed: 0.1,
      core: 0.6,
      pulse: { amplitude: 0.2, period: 2.3, phase: 0 }
    },
    { x: 0.84, y: 0.2, angle: -0.5, spread: 0.08, width: 0.02, length: 1.2, softness: 0.5, intensity: 0.9, streaks: 0.2, streakFreq: 3, streakSpeed: 0, core: 0.8 }
  ], { x: 0.84, y: 0.2, radius: 0.07, intensity: 1.2, streak: 0.8 }),
  lineArt: (context) => merge(
    fiber([[context.aspect * 0.04, 0.86], [context.aspect * 0.4, 0.95], [context.aspect * 0.5, 0.1], [context.aspect * 0.84, 0.2]], 0.012),
    sparks5(context)
  ),
  region: { cx: 0.46, cy: 0.52, w: 0.6, h: 0.5 },
  typography: "crossed",
  burst: { mode: "sung", density: 0.3, every: 2, offset: 0, size: 3.2, tint: [0.8, 0.9, 1] },
  decay: { strength: 1.3, delay: 0.7 },
  starfall: { stars: 380, opening: 3, rain: 60, rainSpeed: 0.3, rainSpread: 0.8, brightness: 1 }
});
var opticsPinhole = optics({
  kind: "optics-pinhole",
  label: "\u6697\u7BB1",
  mood: "quiet",
  light: ({ aspect }) => {
    const distance = (0.45 + 0.02) * aspect;
    return opticsRig([
      { x: -0.02, y: AXIS, angle: 0, spread: -Math.atan(0.15 / distance), width: 0.3, length: 3, softness: 0.4, intensity: 0.8, streaks: 0.3, streakFreq: 6, streakSpeed: 0.05, core: 0.3, reach: distance + 0.3 }
    ], { x: 0.45, y: AXIS, radius: 0.03, intensity: 1, streak: 0.3 });
  },
  lineArt: (context) => merge(pinholeBox(context.aspect * 0.45 + 0.15, AXIS, 0.3, 0.3), sparks5(context)),
  region: { cx: 0.2, cy: 0.52, w: 0.3, h: 0.7 },
  heroSize: 0.07,
  typography: "vertical",
  decay: { strength: 0.6, delay: 1.6 }
});
var opticsTelescope = optics({
  kind: "optics-telescope",
  label: "\u671B\u8FDC",
  mood: "loud",
  light: ({ aspect }) => opticsRig([0.3, 0.5].flatMap((y) => [
    ray(aspect, [-0.02, y], [0.28, y], { width: 0.02 }),
    ray(aspect, [0.28, y], [0.62, AXIS]),
    ray(aspect, [0.72, AXIS + (y - AXIS) * 0.3], [1.02, AXIS + (y - AXIS) * 0.3], { width: 0.02, intensity: 1.1 }, true)
  ]), { x: 0.62, y: AXIS, radius: 0.05, intensity: 1, streak: 0.8 }),
  lineArt: (context) => merge(
    lens(context.aspect * 0.28, AXIS, 0.36, true, context.aspect),
    lens(context.aspect * 0.72, AXIS, 0.12, true, context.aspect, { delay: 0.1 }),
    ...[0.3, 0.5].map((y, i) => rayArt(context.aspect, [[0.02, y], [0.28, y], [0.62, AXIS], [0.72, AXIS - (y - AXIS) * 0.3], [0.98, AXIS - (y - AXIS) * 0.3]], 0.2 + i * 0.1)),
    focusMark(context.aspect * 0.62, AXIS, { delay: 0.5 }),
    sparks5(context)
  ),
  typography: "horizontal",
  burst: { mode: "sung", density: 0.25, every: 2, offset: 1, size: 3.2, tint: [1, 0.8, 0.55] },
  decay: { strength: 1.2, delay: 0.8 }
});
var opticsRaytrace = optics({
  kind: "optics-raytrace",
  label: "\u8FFD\u8FF9",
  mood: "loud",
  light: ({ aspect, random }) => {
    const points = Array.from({ length: 7 }, (_, i) => [0.05 + i / 6 * 0.9, 0.1 + random() * 0.55]);
    return opticsRig(
      points.slice(0, 6).map((point, i) => ray(aspect, point, points[i + 1], { intensity: 0.8, width: 0.012 })),
      { x: points[0][0], y: points[0][1], radius: 0.05, intensity: 0.9, streak: 0.6 }
    );
  },
  lineArt: ({ aspect, random }) => {
    const art = [];
    for (let k = 0; k < 4; k += 1) {
      const points = Array.from({ length: 6 }, (_, i) => [0.05 + i / 5 * 0.9, 0.08 + random() * 0.6]);
      art.push(rayArt(aspect, points, 0.1 + k * 0.1));
    }
    return merge(...art, scatteredSparks({ aspect, count: 16, random, delay: 0.3 }));
  },
  typography: "crossed",
  decay: { strength: 1.3, delay: 0.7 }
});
var OPTICS_PROFILES = [
  opticsConvex,
  opticsConcave,
  opticsMirror,
  opticsRefract,
  opticsBench,
  opticsPeriscope,
  opticsFiber,
  opticsPinhole,
  opticsTelescope,
  opticsRaytrace
];

// folia:src/components/visualizer/lumiere/rigs/prism.ts
var prism = familyOf("prism", { starfall: { ...STARFALL, rain: 50 } });
var sparks6 = ({ aspect, random }) => scatteredSparks({ aspect, count: 16, random, delay: 0.3 });
var tinted = (tint, overrides) => shaft({
  spread: 0.012,
  width: 0.012,
  length: 1.4,
  intensity: 0.7,
  streaks: 0.2,
  streakFreq: 3,
  core: 0.7,
  sway: void 0,
  tint,
  ...overrides
});
var prismSplit = prism({
  kind: "prism-split",
  label: "\u5206\u5149",
  mood: "loud",
  light: rig([
    shaft({ x: -0.02, y: 0.36, angle: 0.08, spread: 0.01, width: 0.02, length: 3, intensity: 0.9, streaks: 0.2, sway: void 0, reach: 0.78 }),
    shaft({
      x: 0.42,
      y: 0.4,
      angle: 0.3,
      spread: 0.2,
      width: 0.02,
      length: 1.1,
      softness: 0.4,
      intensity: 1.1,
      streaks: 0.35,
      streakFreq: 9,
      core: 0.2,
      spectrum: 1,
      sway: { amplitude: 0.03, period: 11, phase: 0 }
    })
  ], { density: 0.9 }, { ...GLARE, x: 0.42, y: 0.4, radius: 0.06, intensity: 1, streak: 0.3 }),
  lineArt: (context) => mergeSpecs(prismTriangle({ cx: context.aspect * 0.42, cy: 0.42, size: 0.2, alpha: 0.8 }), sparks6(context)),
  region: { cx: 0.62, cy: 0.66, w: 0.6, h: 0.44 },
  typography: "horizontal",
  burst: { mode: "sung", density: 0.3, every: 2, offset: 1, size: 3.4, tint: [0.8, 0.9, 1] },
  decay: { strength: 1.2, delay: 0.8 }
});
var prismBand = prism({
  kind: "prism-band",
  label: "\u5149\u8C31\u5E26",
  mood: "neutral",
  light: rig([shaft({
    x: -0.05,
    y: 0.4,
    angle: 0.12,
    spread: 0.05,
    width: 0.16,
    length: 2.5,
    softness: 0.4,
    intensity: 0.9,
    streaks: 0.25,
    streakFreq: 6,
    core: 0.3,
    spectrum: 1,
    sway: { amplitude: 0.02, period: 14, phase: 0 }
  })], { density: 0.8 }, null),
  region: { cx: 0.5, cy: 0.56, w: 0.72, h: 0.46 },
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var prismFringe = prism({
  kind: "prism-fringe",
  label: "\u8679\u8FB9",
  mood: "quiet",
  light: rig([
    shaft({ spread: 0.1, softness: 0.3, spectrum: 0.35, intensity: 0.9 }),
    shaft({ spread: 0.3, length: 0.6, softness: 0.9, intensity: 0.25, streaks: 0.8, streakFreq: 24, core: 0.4, spectrum: 0.5 })
  ]),
  lineArt: (context) => standardArt(context),
  region: { cx: 0.5, cy: 0.5, w: 0.72, h: 0.62 },
  typography: "vertical",
  decay: { strength: 0.7, delay: 1.4 }
});
var prismShard = prism({
  kind: "prism-shard",
  label: "\u788E\u6676",
  mood: "loud",
  light: ({ random }) => ({
    beams: Array.from({ length: 5 }, (_, i) => shaft({
      x: 0.15 + random() * 0.7,
      y: 0.15 + random() * 0.5,
      angle: random() * Math.PI * 2,
      spread: 0.12,
      width: 0.01,
      length: 0.5,
      softness: 0.5,
      intensity: 0.8,
      streaks: 0.3,
      streakFreq: 6,
      core: 0.3,
      spectrum: 1,
      reach: 0.5 + random() * 0.3,
      sway: { amplitude: 0.1, period: 9 + i, phase: random() }
    })),
    fog: { density: 0.9, tyndallBase: 0.12, scale: 2.4, driftX: 8e-3, driftY: -0.03, warp: 0.9, ambient: 0.03 },
    glare: null
  }),
  lineArt: ({ aspect, random }) => merge(shards(aspect, random, 8), scatteredSparks({ aspect, count: 18, random, delay: 0.3 })),
  typography: "crossed",
  burst: { mode: "sweep", density: 0.4, every: 3, offset: 0, size: 3, tint: [0.85, 0.9, 1] },
  decay: { strength: 1.3, delay: 0.7 }
});
var prismLines = prism({
  kind: "prism-lines",
  label: "\u8C31\u7EBF",
  mood: "quiet",
  light: rig([
    tinted([1, 0.35, 0.3], { x: 0.22, y: -0.05, angle: Math.PI / 2 }),
    tinted([1, 0.8, 0.3], { x: 0.36, y: -0.05, angle: Math.PI / 2, intensity: 0.5 }),
    tinted([0.5, 1, 0.5], { x: 0.47, y: -0.05, angle: Math.PI / 2, intensity: 0.8 }),
    tinted([0.4, 0.8, 1], { x: 0.61, y: -0.05, angle: Math.PI / 2, intensity: 0.6 }),
    tinted([0.6, 0.45, 1], { x: 0.78, y: -0.05, angle: Math.PI / 2, intensity: 0.45 })
  ], { density: 0.7, ambient: 0.015 }, null),
  lineArt: ({ aspect, random }) => merge(spectrumLines(aspect * 0.12, aspect * 0.88, 0.84, 0.16, random, 18), scatteredSparks({ aspect, count: 10, random, delay: 0.3 })),
  region: { cx: 0.5, cy: 0.48, w: 0.72, h: 0.6 },
  typography: "vertical",
  decay: { strength: 0.6, delay: 1.6 }
});
var prismMerge = prism({
  kind: "prism-merge",
  label: "\u5408\u5149",
  mood: "neutral",
  light: rig([
    tinted([1, 0.35, 0.3], { x: -0.02, y: 0.18, angle: 0.47, reach: 0.72, intensity: 0.8 }),
    tinted([0.45, 1, 0.45], { x: -0.02, y: 0.4, angle: 0.1, reach: 0.62, intensity: 0.8 }),
    tinted([0.4, 0.6, 1], { x: -0.02, y: 0.66, angle: -0.29, reach: 0.68, intensity: 0.8 }),
    shaft({ x: 0.36, y: 0.46, angle: 0.02, spread: 0.02, width: 0.02, length: 2, intensity: 1.1, streaks: 0.2, streakFreq: 3, core: 0.7, sway: void 0 })
  ], { density: 0.9 }, { ...GLARE, x: 0.36, y: 0.46, radius: 0.06, intensity: 1.1, streak: 0.5 }),
  lineArt: (context) => mergeSpecs(prismTriangle({ cx: context.aspect * 0.34, cy: 0.46, size: 0.12, alpha: 0.6 }), sparks6(context)),
  typography: "crossed",
  decay: { strength: 1, delay: 1 }
});
var prismCube = prism({
  kind: "prism-cube",
  label: "\u5206\u675F",
  mood: "neutral",
  // 射程按高度单位算，光源 x 是画面宽度的比例：入射光要走到分光镜中心，得乘画幅比。
  light: ({ aspect }) => rig([
    shaft({ x: -0.02, y: 0.34, angle: 0, spread: 0.01, width: 0.03, length: 3, intensity: 0.9, streaks: 0.2, sway: void 0, reach: (0.42 + 0.02) * aspect }),
    shaft({ x: 0.42, y: 0.34, angle: 0, spread: 0.01, width: 0.03, length: 3, intensity: 0.7, streaks: 0.2, sway: void 0, spectrum: 0.3 }),
    shaft({ x: 0.42, y: 0.34, angle: Math.PI / 2, spread: 0.01, width: 0.03, length: 3, intensity: 0.6, streaks: 0.2, sway: void 0, spectrum: 0.3 })
  ], { density: 0.9 }, { ...GLARE, x: 0.42, y: 0.34, radius: 0.05, intensity: 0.9, streak: 0.4 })(),
  lineArt: (context) => merge(cubeSplitter(context.aspect * 0.42, 0.34, 0.08), scatteredSparks({ aspect: context.aspect, count: 12, random: context.random, delay: 0.3 })),
  region: { cx: 0.6, cy: 0.62, w: 0.6, h: 0.44 },
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var prismWheel = prism({
  kind: "prism-wheel",
  label: "\u8679\u6247",
  mood: "loud",
  light: rig([0, 1, 2].map((k) => shaft({
    x: 0.5,
    y: 0.08,
    angle: Math.PI / 2 + (k - 1) * 0.7,
    spread: 0.18,
    width: 0.01,
    length: 1.1,
    softness: 0.4,
    intensity: 0.8,
    streaks: 0.3,
    streakFreq: 8,
    core: 0.2,
    spectrum: 1,
    sway: { amplitude: 0.5, period: 16, phase: k / 3 }
  })), { density: 0.9 }, { ...GLARE, y: 0.08, radius: 0.1, intensity: 1.1, streak: 0.4 }),
  lineArt: (context) => mergeSpecs(prismTriangle({ cx: context.aspect * 0.5, cy: 0.1, size: 0.1, alpha: 0.6 }), sparks6(context)),
  typography: "crossed",
  decay: { strength: 1.2, delay: 0.8 }
});
var prismDroplet = prism({
  kind: "prism-droplet",
  label: "\u8679\u9713",
  mood: "quiet",
  light: rig(
    [shaft({ x: 0.5, y: 1.2, angle: -Math.PI / 2, spread: 0.55, width: 0.1, length: 1.1, softness: 0.25, intensity: 0.55, streaks: 0.1, core: 0, spectrum: 1, sway: void 0 })],
    { density: 0.7, driftY: 0.02 },
    null
  ),
  lineArt: ({ aspect, random }) => merge(rainbowArcs(aspect * 0.5, 1.02, 0.62), scatteredSparks({ aspect, count: 12, random, delay: 0.3 })),
  starfall: { ...STARFALL, rain: 160, rainSpeed: 0.5, rainSpread: 1.6, brightness: 0.8 },
  region: { cx: 0.5, cy: 0.46, w: 0.72, h: 0.6 },
  typography: "vertical",
  decay: { strength: 0.6, delay: 1.6 }
});
var prismSweep = prism({
  kind: "prism-sweep",
  label: "\u626B\u8C31",
  mood: "neutral",
  light: rig([shaft({
    x: 0.5,
    y: -0.1,
    angle: Math.PI / 2,
    spread: 0.08,
    width: 0.1,
    length: 1.4,
    softness: 0.4,
    intensity: 0.95,
    streaks: 0.2,
    core: 0.3,
    spectrum: 1,
    sway: { amplitude: 0.35, period: 8, phase: 0 }
  })], { density: 0.9 }, { ...GLARE, y: -0.05, intensity: 0.6 }),
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var PRISM_PROFILES = [
  prismSplit,
  prismBand,
  prismFringe,
  prismShard,
  prismLines,
  prismMerge,
  prismCube,
  prismWheel,
  prismDroplet,
  prismSweep
];

// folia:src/components/visualizer/lumiere/rigs/stage.ts
var stage = familyOf("stage", {
  motes: { ...MOTES, count: 200 }
});
var HAZE = { ...FOG, density: 1.25, tyndallBase: 0.08, scale: 2, driftX: 0.01, driftY: -0.015, warp: 1.1, ambient: 0.035 };
var lamp = (aspect, a, b, overrides = {}) => shaft({
  x: a[0],
  y: a[1],
  angle: Math.atan2(b[1] - a[1], (b[0] - a[0]) * aspect),
  spread: 0.08,
  width: 0.03,
  length: 1.3,
  softness: 0.55,
  intensity: 1,
  streaks: 0.4,
  streakFreq: 6,
  core: 0.6,
  sway: void 0,
  ...overrides
});
var stageRig = (beams, glare = null, fog = {}) => ({ beams, fog: { ...HAZE, ...fog }, glare });
var lampsArt = (context, beams) => merge(
  ...beams.map((beam, i) => lampHead(beam.x * context.aspect, beam.y, beam.angle, 0.035, { delay: i * 0.05 })),
  scatteredSparks({ aspect: context.aspect, count: 10, random: context.random, delay: 0.3 })
);
var withLamps = (build) => ({
  light: build,
  lineArt: (context) => lampsArt(context, build(context).beams)
});
var CENTER = [0.5, 0.56];
var stageSpot = stage({
  kind: "stage-spot",
  label: "\u72EC\u5149",
  mood: "neutral",
  ...withLamps(({ aspect }) => stageRig([lamp(aspect, [0.14, 0.02], CENTER, { sway: { amplitude: 0.02, period: 12, phase: 0 } })], { x: 0.14, y: 0.02, radius: 0.08, intensity: 0.9, streak: 0.5 })),
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var stageCross = stage({
  kind: "stage-cross",
  label: "\u4EA4\u53C9",
  mood: "loud",
  ...withLamps(({ aspect }) => stageRig([
    lamp(aspect, [0.06, 0.02], CENTER, { sway: { amplitude: 0.03, period: 9, phase: 0 } }),
    lamp(aspect, [0.94, 0.02], CENTER, { sway: { amplitude: 0.03, period: 9, phase: 0.5 } })
  ], { x: 0.5, y: 0.56, radius: 0.06, intensity: 0.6, streak: 0.6 })),
  typography: "crossed",
  burst: { mode: "sung", density: 0.3, every: 2, offset: 1, size: 3.4, tint: [1, 0.75, 0.5] },
  decay: { strength: 1.3, delay: 0.7 }
});
var stageSearch = stage({
  kind: "stage-search",
  label: "\u63A2\u7167",
  mood: "loud",
  ...withLamps(() => stageRig([0.15, 0.38, 0.62, 0.85].map((x, i) => shaft({
    x,
    y: 1.02,
    angle: -Math.PI / 2,
    spread: 0.035,
    width: 0.03,
    length: 1.4,
    softness: 0.5,
    intensity: 0.8,
    streaks: 0.3,
    streakFreq: 5,
    core: 0.6,
    sway: { amplitude: 0.45, period: 7 + i * 1.3, phase: i * 0.27 }
  })))),
  region: { cx: 0.5, cy: 0.44, w: 0.72, h: 0.46 },
  typography: "horizontal",
  decay: { strength: 1.3, delay: 0.7 }
});
var stageFootlight = stage({
  kind: "stage-footlight",
  label: "\u811A\u5149",
  mood: "quiet",
  ...withLamps(() => stageRig([0.25, 0.5, 0.75].map((x) => shaft({
    x,
    y: 1.03,
    angle: -Math.PI / 2,
    spread: 0.22,
    width: 0.08,
    length: 0.7,
    softness: 0.9,
    intensity: 0.6,
    streaks: 0.4,
    streakFreq: 10,
    core: 0.3,
    tint: [1, 0.8, 0.6],
    sway: void 0
  })), null, { driftY: -0.03 })),
  region: { cx: 0.5, cy: 0.46, w: 0.5, h: 0.62 },
  typography: "vertical",
  decay: { strength: 0.6, delay: 1.6 }
});
var stageBacklight = stage({
  kind: "stage-backlight",
  label: "\u9006\u5149",
  mood: "neutral",
  light: () => stageRig(Array.from({ length: 6 }, (_, k) => shaft({
    x: 0.5,
    y: 0.5,
    angle: k / 6 * Math.PI * 2 + 0.5,
    spread: 0.12,
    width: 0.02,
    length: 0.8,
    softness: 0.7,
    intensity: 0.6,
    streaks: 0.6,
    streakFreq: 10,
    core: 0.4,
    sway: { amplitude: 0.05, period: 11, phase: k / 6 }
  })), { x: 0.5, y: 0.5, radius: 0.22, intensity: 1.2, streak: 0.8 }),
  lineArt: ({ aspect, random }) => scatteredSparks({ aspect, count: 18, random, delay: 0.3 }),
  region: { cx: 0.5, cy: 0.5, w: 0.72, h: 0.5 },
  typography: "crossed",
  decay: { strength: 1, delay: 1 }
});
var stagePinspot = stage({
  kind: "stage-pinspot",
  label: "\u9488\u5149",
  mood: "quiet",
  ...withLamps(({ aspect }) => stageRig([lamp(aspect, [0.5, 0.02], CENTER, { spread: 0.03, width: 0.01, intensity: 0.9, core: 0.9 })], null, { ambient: 0.015 })),
  typography: "horizontal",
  decay: { strength: 0.6, delay: 1.6 }
});
var stageStrobe = stage({
  kind: "stage-strobe",
  label: "\u9891\u95EA",
  mood: "loud",
  ...withLamps(({ aspect }) => stageRig([0.1, 0.36, 0.64, 0.9].map((x, i) => lamp(aspect, [x, 0.02], [0.5, 0.6], {
    spread: 0.08,
    intensity: 0.55,
    pulse: { amplitude: 0.95, period: 0.5, phase: i * 0.25 }
  })), { x: 0.5, y: 0.02, radius: 0.2, intensity: 0.6, streak: 0.4 })),
  typography: "crossed",
  burst: { mode: "sweep", density: 0.5, every: 2, offset: 0, size: 3, tint: [1, 0.9, 0.8] },
  decay: { strength: 1.4, delay: 0.6 }
});
var stageCurtain = stage({
  kind: "stage-curtain",
  label: "\u5E55\u7F1D",
  mood: "quiet",
  light: () => stageRig(
    [shaft({ spread: 0.01, width: 0.04, length: 1.6, softness: 0.5, intensity: 0.9, streaks: 0.3, core: 0.7, sway: void 0 })],
    { x: 0.5, y: -0.02, radius: 0.08, intensity: 0.8, streak: 0.5 },
    { ambient: 0.02 }
  ),
  lineArt: ({ aspect, random }) => merge(curtains(aspect, 0.06), scatteredSparks({ aspect, count: 8, random, delay: 0.3, region: [0.3, 0.2, 0.7, 0.9] })),
  region: { cx: 0.5, cy: 0.5, w: 0.3, h: 0.66 },
  typography: "vertical",
  decay: { strength: 0.6, delay: 1.6 }
});
var stageLaser = stage({
  kind: "stage-laser",
  label: "\u6FC0\u5149",
  mood: "loud",
  ...withLamps(() => stageRig(Array.from({ length: 6 }, (_, k) => shaft({
    x: 0.5,
    y: 1.02,
    angle: -Math.PI / 2 + (k - 2.5) * 0.22,
    spread: 2e-3,
    width: 4e-3,
    length: 2,
    softness: 0.3,
    intensity: 1.2,
    streaks: 0,
    core: 0.9,
    sway: { amplitude: 0.25, period: 4.5, phase: k * 0.08 }
  })), { x: 0.5, y: 1, radius: 0.06, intensity: 1, streak: 0.6 }, { density: 1.4 })),
  region: { cx: 0.5, cy: 0.4, w: 0.72, h: 0.46 },
  typography: "horizontal",
  decay: { strength: 1.3, delay: 0.7 }
});
var stageProjector = stage({
  kind: "stage-projector",
  label: "\u653E\u6620",
  mood: "neutral",
  light: () => stageRig([shaft({
    x: 0.12,
    y: 0.4,
    angle: 0.05,
    spread: 0.2,
    width: 0.02,
    length: 1.8,
    softness: 0.4,
    intensity: 1,
    streaks: 0.5,
    streakFreq: 9,
    core: 0.4,
    sway: void 0,
    pulse: { amplitude: 0.05, period: 0.12, phase: 0 }
  })], { x: 0.12, y: 0.4, radius: 0.05, intensity: 1, streak: 0.4 }),
  lineArt: ({ aspect, random }) => merge(projector(aspect * 0.12, 0.4, 0.1), scatteredSparks({ aspect, count: 10, random, delay: 0.3 })),
  motes: { ...MOTES, count: 380, driftX: 4e-3, swirl: 0.03, gain: 1.8 },
  region: { cx: 0.62, cy: 0.5, w: 0.44, h: 0.58 },
  typography: "vertical",
  decay: { strength: 1, delay: 1 }
});
var STAGE_PROFILES = [
  stageSpot,
  stageCross,
  stageSearch,
  stageFootlight,
  stageBacklight,
  stagePinspot,
  stageStrobe,
  stageCurtain,
  stageLaser,
  stageProjector
];

// folia:src/components/visualizer/lumiere/rigs/wave.ts
var wave = familyOf("wave", { starfall: { ...STARFALL, rain: 40 } });
var sparks7 = ({ aspect, random }) => scatteredSparks({ aspect, count: 12, random, delay: 0.3 });
var fringes = (spec) => ({ wave: spec });
var waveSlits = wave({
  kind: "wave-slits",
  label: "\u53CC\u7F1D",
  mood: "neutral",
  light: rig(
    [shaft({ spread: 0.05, width: 0.04, length: 0.6, intensity: 0.9 })],
    { density: 0.9 },
    GLARE,
    fringes({ mode: "slits", cx: 0.5, cy: 0.72, radius: 0.3, frequency: 5, speed: 0.4, strength: 0.55 })
  ),
  lineArt: (context) => mergeSpecs(
    slitBarrier({ cx: context.aspect * 0.5, y: 0.3, width: context.aspect * 0.5, gap: 0.012, separation: 0.08 }),
    viewfinderFrame({ aspect: context.aspect, left: 0.2, top: 0.52, right: 0.8, bottom: 0.92, delay: 0.2, alpha: 0.28 }),
    sparks7(context)
  ),
  region: { cx: 0.5, cy: 0.5, w: 0.72, h: 0.5 },
  typography: "crossed",
  decay: { strength: 1, delay: 1 }
});
var waveNewton = wave({
  kind: "wave-newton",
  label: "\u725B\u987F\u73AF",
  mood: "quiet",
  light: rig(
    [shaft({ spread: 0.06, width: 0.04, length: 0.6, intensity: 0.6 })],
    { density: 0.7 },
    { ...GLARE, intensity: 0.5 },
    fringes({ mode: "rings", cx: 0.5, cy: 0.5, radius: 0.4, frequency: 5, speed: 0.3, strength: 0.5, shield: 0.75 })
  ),
  lineArt: (context) => merge(rings(context.aspect * 0.5, 0.5, 0.4, 6), sparks7(context)),
  region: { cx: 0.5, cy: 0.5, w: 0.4, h: 0.62 },
  typography: "vertical",
  decay: { strength: 0.6, delay: 1.6 }
});
var waveAiry = wave({
  kind: "wave-airy",
  label: "\u827E\u91CC\u6591",
  mood: "quiet",
  light: rig(
    [shaft({ x: 0.5, y: -0.05, spread: 0.02, width: 0.01, length: 0.6, intensity: 0.5, reach: 0.4 })],
    { density: 0.6 },
    { x: 0.5, y: 0.4, radius: 0.04, intensity: 1, streak: 0.4 },
    fringes({ mode: "airy", cx: 0.5, cy: 0.4, radius: 0.3, frequency: 3, speed: 0, strength: 0.7 })
  ),
  lineArt: (context) => merge(rings(context.aspect * 0.5, 0.4, 0.3, 4, { alpha: 0.3 }), sparks7(context)),
  region: { cx: 0.5, cy: 0.72, w: 0.72, h: 0.36 },
  typography: "horizontal",
  decay: { strength: 0.6, delay: 1.6 }
});
var waveGrating = wave({
  kind: "wave-grating",
  label: "\u5149\u6805",
  mood: "neutral",
  light: rig([
    shaft({ spread: 0.01, width: 0.03, length: 2, intensity: 0.9, reach: 0.32, sway: void 0 }),
    ...[-2, -1, 0, 1, 2].map((k) => shaft({
      y: 0.3,
      angle: Math.PI / 2 + k * 0.32,
      spread: 0.02,
      width: 0.02,
      length: 1.2,
      intensity: 0.8 - Math.abs(k) * 0.15,
      streaks: 0.2,
      core: 0.6,
      spectrum: k === 0 ? 0 : 0.8,
      sway: void 0
    }))
  ], { density: 0.9 }, { ...GLARE, y: 0.3, radius: 0.05, intensity: 0.9, streak: 0.6 }),
  lineArt: (context) => merge(grating(context.aspect * 0.5, 0.3, context.aspect * 0.4, 16), sparks7(context)),
  region: { cx: 0.5, cy: 0.7, w: 0.72, h: 0.38 },
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var waveSources = wave({
  kind: "wave-sources",
  label: "\u6CE2\u53E0",
  mood: "loud",
  light: rig(
    [shaft({ spread: 0.15, intensity: 0.4 })],
    { density: 0.8 },
    { ...GLARE, intensity: 0.5 },
    fringes({ mode: "sources", cx: 0.5, cy: 0.5, radius: 0.46, frequency: 4, speed: 1.2, strength: 0.6, separation: 0.14 })
  ),
  lineArt: (context) => merge(twoSources(context.aspect * 0.5, 0.5, 0.14, 0.3), sparks7(context)),
  typography: "crossed",
  burst: { mode: "sung", density: 0.3, every: 2, offset: 0, size: 3.2, tint: [0.85, 0.9, 1] },
  decay: { strength: 1.3, delay: 0.7 }
});
var waveMoire = wave({
  kind: "wave-moire",
  label: "\u83AB\u5C14",
  mood: "neutral",
  light: rig([
    shaft({ spread: 0.2, width: 0.3, length: 1.3, softness: 0.6, intensity: 0.6, streaks: 0, core: 0.2, gobo: { pattern: "blinds", frequency: 22, duty: 0.5, drift: 0.02 }, sway: void 0 }),
    shaft({ angle: Math.PI / 2 + 0.06, spread: 0.2, width: 0.3, length: 1.3, softness: 0.6, intensity: 0.6, streaks: 0, core: 0.2, gobo: { pattern: "blinds", frequency: 23, duty: 0.5, drift: -0.02 }, sway: { amplitude: 0.03, period: 14, phase: 0 } })
  ], { density: 0.8 }, { ...GLARE, intensity: 0.5 }),
  lineArt: (context) => merge(moire(context.aspect * 0.5, 0.32, 0.4, 24, 0.08), sparks7(context)),
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var waveFilm = wave({
  kind: "wave-film",
  label: "\u8584\u819C",
  mood: "quiet",
  light: rig(
    [shaft({
      spread: 0.4,
      width: 0.3,
      length: 1.2,
      softness: 0.95,
      intensity: 0.45,
      streaks: 0.6,
      streakFreq: 3,
      streakSpeed: 0.2,
      core: 0.2,
      spectrum: 1,
      sway: { amplitude: 0.15, period: 13, phase: 0 }
    })],
    { density: 0.7 },
    null,
    fringes({ mode: "rings", cx: 0.5, cy: 0.4, radius: 0.3, frequency: 1.6, speed: 0.6, strength: 0.25 })
  ),
  lineArt: (context) => merge(
    { paths: [circle(context.aspect * 0.5, 0.4, 0.3, { width: 16e-4, alpha: 0.45 }), circle(context.aspect * 0.5 - 0.08, 0.3, 0.06, { width: 1e-3, alpha: 0.3, delay: 0.2 })], nodes: [] },
    sparks7(context)
  ),
  region: { cx: 0.5, cy: 0.5, w: 0.4, h: 0.62 },
  typography: "vertical",
  decay: { strength: 0.6, delay: 1.6 }
});
var wavePolar = wave({
  kind: "wave-polar",
  label: "\u504F\u632F",
  mood: "neutral",
  // 第一束穿过第一片、走到第二片；第二束从第二片出发，随偏振片转动一明一暗（按画幅比例定位）。
  light: ({ aspect }) => {
    const second = aspect * 0.5 + 0.12;
    return rig([
      shaft({ x: -0.02, y: 0.36, angle: 0, spread: 0.02, width: 0.14, length: 3, intensity: 0.8, streaks: 0.2, core: 0.4, reach: second + 0.02 * aspect, sway: void 0 }),
      shaft({ x: second / aspect, y: 0.36, angle: 0, spread: 0.02, width: 0.14, length: 3, intensity: 0.7, streaks: 0.2, core: 0.4, sway: void 0, pulse: { amplitude: 0.9, period: 6, phase: 0 } })
    ], { density: 0.8 }, null)();
  },
  lineArt: (context) => merge(polarizers(context.aspect * 0.5, 0.36, 0.1, 0.24, Math.PI / 3), sparks7(context)),
  region: { cx: 0.5, cy: 0.7, w: 0.72, h: 0.36 },
  typography: "horizontal",
  decay: { strength: 1, delay: 1 }
});
var waveStanding = wave({
  kind: "wave-standing",
  label: "\u9A7B\u6CE2",
  mood: "loud",
  light: rig([0.26, 0.34, 0.42].map((y, i) => shaft({
    x: -0.02,
    y,
    angle: 0,
    spread: 4e-3,
    width: 0.01,
    length: 3,
    intensity: 0.7,
    streaks: 0.6,
    streakFreq: 4,
    core: 0.8,
    sway: void 0,
    pulse: { amplitude: 0.6, period: 1.2, phase: i / 3 }
  })), { density: 0.9 }, null),
  lineArt: (context) => merge(standingWave(context.aspect * 0.08, context.aspect * 0.92, 0.34, 0.07, 6), sparks7(context)),
  typography: "crossed",
  decay: { strength: 1.3, delay: 0.7 }
});
var waveHolo = wave({
  kind: "wave-holo",
  label: "\u5168\u606F",
  mood: "loud",
  light: rig(
    [shaft({
      spread: 0.3,
      width: 0.3,
      length: 1.3,
      softness: 0.8,
      intensity: 0.8,
      streaks: 0.3,
      core: 0.3,
      spectrum: 0.8,
      gobo: { pattern: "lattice", frequency: 24, duty: 0.7, drift: 0.15 },
      sway: { amplitude: 0.1, period: 10, phase: 0 }
    })],
    { density: 0.8 },
    { ...GLARE, intensity: 0.6 },
    fringes({ mode: "rings", cx: 0.5, cy: 0.5, radius: 0.5, frequency: 8, speed: 1, strength: 0.15 })
  ),
  lineArt: (context) => merge(gridPanel(context.aspect * 0.3, 0.15, context.aspect * 0.4, 0.7, 6, 8, true, { alpha: 0.3 }), sparks7(context)),
  region: { cx: 0.5, cy: 0.5, w: 0.4, h: 0.62 },
  typography: "vertical",
  decay: { strength: 1.3, delay: 0.7 }
});
var WAVE_PROFILES = [
  waveSlits,
  waveNewton,
  waveAiry,
  waveGrating,
  waveSources,
  waveMoire,
  waveFilm,
  wavePolar,
  waveStanding,
  waveHolo
];

// folia:src/components/visualizer/lumiere/rigs/zenith.ts
var zenith = familyOf("zenith");
var zenithShaft = zenith({
  kind: "zenith-shaft",
  label: "\u5929\u4E95",
  mood: "neutral",
  light: rig([shaft(), fan(), fan({ spread: 0.55, length: 0.42, softness: 1, intensity: 0.16, streaks: 0.9, streakFreq: 40, streakSpeed: -0.03, core: 0.2, sway: void 0 })]),
  typography: "crossed",
  decay: { strength: 1, delay: 1 },
  starfall: STARFALL
});
var zenithFan = zenith({
  kind: "zenith-fan",
  label: "\u6247\u5149",
  mood: "loud",
  light: rig([-2, -1, 0, 1, 2].map((k) => shaft({
    angle: DOWN + k * 0.24,
    spread: 0.035,
    width: 0.012,
    length: 0.9,
    intensity: 0.7 - Math.abs(k) * 0.08,
    streaks: 0.4,
    streakFreq: 5,
    sway: { amplitude: 0.05, period: 11, phase: k * 0.1 }
  }))),
  typography: "horizontal",
  decay: { strength: 1.2, delay: 0.8 },
  starfall: { ...STARFALL, rain: 110, rainSpread: 0.6 }
});
var zenithHalo = zenith({
  kind: "zenith-halo",
  label: "\u5723\u73AF",
  mood: "neutral",
  light: rig([shaft({ spread: 0.07 }), fan({ spread: 0.42, intensity: 0.24 })], {}, { ...GLARE, radius: 0.2, intensity: 1.2, streak: 0.7 }),
  lineArt: (context) => mergeSpecs(
    protractorHalo({ cx: context.aspect * 0.5, cy: 0.03, radius: 0.42, alpha: 0.7, spokeStep: Math.PI / 18 }),
    protractorHalo({ cx: context.aspect * 0.5, cy: 0.03, radius: 0.24, alpha: 0.4, delay: 0.2 }),
    scatteredSparks({ aspect: context.aspect, count: 20, random: context.random, delay: 0.3 })
  ),
  region: { cx: 0.5, cy: 0.5, w: 0.72, h: 0.62 },
  typography: "vertical",
  decay: { strength: 0.8, delay: 1.2 },
  starfall: STARFALL
});
var zenithDrift = zenith({
  kind: "zenith-drift",
  label: "\u6E38\u5149",
  mood: "quiet",
  light: rig([shaft({ sway: { amplitude: 0.2, period: 9, phase: 0 }, intensity: 0.85 }), fan({ intensity: 0.2, sway: { amplitude: 0.2, period: 9, phase: 0 } })], { density: 0.9 }),
  typography: "horizontal",
  decay: { strength: 0.7, delay: 1.4 },
  camera: { push: 0.02, driftX: 0.01, driftY: 0 }
});
var zenithTwin = zenith({
  kind: "zenith-twin",
  label: "\u53CC\u67F1",
  mood: "neutral",
  light: rig([
    shaft({ x: 0.33, spread: 0.06, sway: { amplitude: 0.06, period: 12, phase: 0 } }),
    shaft({ x: 0.67, spread: 0.06, sway: { amplitude: 0.06, period: 12, phase: 0.5 } })
  ], {}, null),
  lineArt: (context) => mergeSpecs(
    viewfinderFrame({ aspect: context.aspect, left: 0.07, top: 0.21, right: 0.93, bottom: 0.8, alpha: 0.32 }),
    scatteredSparks({ aspect: context.aspect, count: 18, random: context.random, delay: 0.2 })
  ),
  typography: "crossed",
  decay: { strength: 1, delay: 1 }
});
var zenithRain = zenith({
  kind: "zenith-rain",
  label: "\u5149\u96E8",
  mood: "loud",
  light: rig([0.18, 0.34, 0.5, 0.66, 0.82, 0.42].map((x, i) => shaft({
    x,
    spread: 0.012,
    width: 0.01,
    length: 1.1,
    intensity: 0.45,
    streaks: 0.7,
    streakFreq: 3,
    pulse: { amplitude: 0.35, period: 1.7 + i * 0.37, phase: i * 0.21 },
    sway: void 0
  })), { driftY: 0.05 }, { ...GLARE, intensity: 0.5 }),
  typography: "vertical",
  decay: { strength: 1.3, delay: 0.6 },
  starfall: { ...STARFALL, rain: 220, rainSpeed: 0.45, rainSpread: 1.4, brightness: 1.1 }
});
var zenithWell = zenith({
  kind: "zenith-well",
  label: "\u5149\u4E95",
  mood: "quiet",
  light: rig([shaft({ spread: 0.05, width: 0.02, length: 1.4, intensity: 0.8, core: 0.9 })], { density: 0.7, ambient: 0.015 }, { ...GLARE, intensity: 0.6 }),
  lineArt: (context) => ({
    paths: [
      { points: ellipse(context.aspect * 0.5, 0.8, 0.26, 0.05), width: 18e-4, alpha: 0.7, delay: 0.1, span: 0.5 },
      { points: ellipse(context.aspect * 0.5, 0.8, 0.17, 0.032), width: 12e-4, alpha: 0.45, delay: 0.2, span: 0.4, dash: [4e-3, 8e-3] }
    ],
    nodes: [{ at: [context.aspect * 0.5, 0.8], size: 0.03, delay: 0.3, twinklePhase: 0 }]
  }),
  motes: { ...MOTES, count: 160 },
  typography: "horizontal",
  decay: { strength: 0.6, delay: 1.6 }
});
var zenithCrown = zenith({
  kind: "zenith-crown",
  label: "\u51A0\u5195",
  mood: "loud",
  light: (context) => ({ ...zenithShaft.light(context), glare: { x: 0.5, y: 0, radius: 0.18, intensity: 1.3, streak: 0.8 } }),
  burst: { mode: "sung", density: 0.4, every: 1, offset: 0, size: 4, tint: [1, 0.6, 0.4] },
  typography: "horizontal",
  decay: { strength: 1.25, delay: 0.7 },
  // 更密更快的光雨。
  starfall: { stars: 520, opening: 2.6, rain: 120, rainSpeed: 0.32, rainSpread: 0.5, brightness: 1.1 },
  camera: { push: 0.05, driftX: 0, driftY: -0.01 }
});
var zenithDescent = zenith({
  kind: "zenith-descent",
  label: "\u5782\u964D",
  mood: "neutral",
  light: rig([shaft({ reveal: 3 }), fan({ reveal: 3.5 })]),
  typography: "crossed",
  decay: { strength: 1, delay: 1 },
  starfall: { ...STARFALL, rain: 40 }
});
var zenithEmber = zenith({
  kind: "zenith-ember",
  label: "\u4F59\u70EC",
  mood: "quiet",
  light: rig([
    shaft({ intensity: 0.45, tint: [1, 0.7, 0.5], pulse: { amplitude: 0.2, period: 5, phase: 0 } }),
    fan({ intensity: 0.12, tint: [1, 0.6, 0.4] })
  ], { density: 1.2, ambient: 0.04, driftY: -0.05 }, { ...GLARE, intensity: 0.4 }),
  motes: { ...MOTES, count: 320, driftY: -0.035, swirl: 0.03, gain: 1.6, ambient: 0.04 },
  region: { cx: 0.5, cy: 0.5, w: 0.72, h: 0.62 },
  typography: "vertical",
  decay: { strength: 1.4, delay: 0.8 },
  camera: { push: 0.02, driftX: 0, driftY: -0.012 }
});
var ZENITH_PROFILES = [
  zenithShaft,
  zenithFan,
  zenithHalo,
  zenithDrift,
  zenithTwin,
  zenithRain,
  zenithWell,
  zenithCrown,
  zenithDescent,
  zenithEmber
];

// folia:src/components/visualizer/lumiere/catalog.ts
var lumiereScaleMask16 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET16 = (4898 ^ lumiereScaleMask16) + Math.imul(523 ^ lumiereScaleMask16, 47868 ^ lumiereScaleMask16) - ((4898 ^ lumiereScaleMask16) + Math.imul(523 ^ lumiereScaleMask16, 47868 ^ lumiereScaleMask16));
var LUMIERE_PROFILES = [
  ...ZENITH_PROFILES,
  ...LATTICE_PROFILES,
  ...PRISM_PROFILES,
  ...CAUSTIC_PROFILES,
  ...OPTICS_PROFILES,
  ...WAVE_PROFILES,
  ...BOTANY_PROFILES,
  ...ASTRAL_PROFILES,
  ...STAGE_PROFILES,
  ...MOTES_PROFILES
];
var BY_KIND = new Map(LUMIERE_PROFILES.map((profile) => [profile.kind, profile]));
var LUMIERE_KINDS = LUMIERE_PROFILES.map((profile) => profile.kind);
var profileOf = (kind) => BY_KIND.get(kind) ?? LUMIERE_PROFILES[0 + LUMIERE_NEUTRAL_OFFSET16];

// folia:src/components/visualizer/lumiere/program.ts
var lumiereScaleMask17 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET17 = (3118931976 ^ lumiereScaleMask17) + Math.imul(1593667296 ^ lumiereScaleMask17, 445441147 ^ lumiereScaleMask17) - ((3118931976 ^ lumiereScaleMask17) + Math.imul(1593667296 ^ lumiereScaleMask17, 445441147 ^ lumiereScaleMask17));
var LUMIERE_TRANSITION_KINDS = ["lights-out", "flare-cut", "focus-pull"];
var DEFAULT_LUMIERE_PARAMS = {
  maxShotDuration: 7,
  maxLinesPerShot: 2,
  longLine: 3.6,
  bridgeGap: 4
};
var RECENT = 3 + LUMIERE_NEUTRAL_OFFSET17;
var BRIDGE_FAMILIES = ["motes", "astral", "zenith"];
var MOODS_BY_KIND = {
  chorus: ["loud", "neutral"],
  lift: ["loud", "neutral"],
  verse: ["quiet", "neutral"],
  breath: ["quiet", "neutral"],
  outro: ["quiet"],
  break: null
};
var moodsForEnergy = (energy) => energy < 0.33 ? ["quiet", "neutral"] : energy < 0.66 ? null : ["neutral", "loud"];
var groupLines = (lines, params) => {
  const groups = [];
  for (const line2 of lines) {
    const duration = line2.renderEndTime - line2.line.startTime;
    const last = groups.at(-1);
    const lastStart = last?.lines[0]?.line.startTime ?? 0;
    const lastLong = last ? last.lines.length === 1 && last.lines[0].renderEndTime - lastStart >= params.longLine : true;
    if (last && !lastLong && duration < params.longLine && last.lines.length < params.maxLinesPerShot && line2.renderEndTime - lastStart <= params.maxShotDuration) {
      last.lines.push(line2);
    } else {
      groups.push({ lines: [line2] });
    }
  }
  return groups;
};
var planShots = (lines, paragraphStart, paragraphEnd, params) => {
  const groups = groupLines(lines, params);
  const shots = [];
  groups.forEach((group, index) => {
    const start = index === 0 ? Math.min(paragraphStart, group.lines[0].line.startTime) : group.lines[0].line.startTime;
    const lyricEnd = Math.max(...group.lines.map((line2) => line2.renderEndTime));
    const nextStart = groups[index + 1]?.lines[0]?.line.startTime ?? paragraphEnd;
    if (nextStart - lyricEnd >= params.bridgeGap) {
      const end = lyricEnd + 0.6;
      shots.push({ lines: group.lines, startTime: start, endTime: end, lyricEndTime: lyricEnd, isBridge: false });
      shots.push({ lines: [], startTime: end, endTime: nextStart, lyricEndTime: nextStart, isBridge: true });
    } else {
      shots.push({ lines: group.lines, startTime: start, endTime: Math.max(nextStart, lyricEnd), lyricEndTime: Math.min(lyricEnd, nextStart), isBridge: false });
    }
  });
  if (groups.length === 0 && paragraphEnd > paragraphStart) {
    shots.push({ lines: [], startTime: paragraphStart, endTime: paragraphEnd, lyricEndTime: paragraphEnd, isBridge: true });
  }
  return shots;
};
var castShot = (options) => {
  const { chain } = options;
  let candidates = LUMIERE_KINDS;
  const narrow = (keep, atLeast = 1) => {
    const next = candidates.filter(keep);
    if (next.length >= atLeast) candidates = next;
  };
  const energy = options.energy ?? null;
  const moods = energy === null ? MOODS_BY_KIND[options.kind] : moodsForEnergy(energy);
  if (options.isBridge) narrow((kind) => BRIDGE_FAMILIES.includes(profileOf(kind).family) && profileOf(kind).mood !== "loud");
  if (moods) narrow((kind) => moods.includes(profileOf(kind).mood));
  narrow((kind) => !chain.recent.includes(kind));
  if (chain.family) narrow((kind) => profileOf(kind).family !== chain.family, 3);
  const random = createRng(`${options.seed}:${options.paragraphIndex}:${options.shotIndex}:cast`);
  return candidates[Math.floor(random() * candidates.length)];
};
var advanceChain = (chain, kind) => {
  chain.recent = [...chain.recent, kind].slice(-RECENT);
  chain.family = profileOf(kind).family;
};

// folia:src/components/visualizer/lumiere/lumiereTransitions.ts
var smooth5 = (value) => {
  const t = Math.min(1, Math.max(0, value));
  return t * t * (3 - 2 * t);
};
var LABELS = { "lights-out": "\u7184\u706F", "flare-cut": "\u95EA\u767D", "focus-pull": "\u62C9\u7126" };
var LUMIERE_TRANSITIONS = Object.fromEntries(
  LUMIERE_TRANSITION_KINDS.map((kind) => [kind, {
    kind,
    label: LABELS[kind],
    duration: (gap) => kind === "focus-pull" ? Math.min(0.6, Math.max(0.35, gap > 0 ? gap * 0.5 : 0.45)) : Math.min(1.1, Math.max(0.5, gap > 0 ? gap * 0.6 : 0.8)),
    enterClamp: kind === "focus-pull" ? [0.3, 0.6] : [0.4, 0.9],
    resolveFrame: (phase, progress) => {
      const near = phase === "exit" ? smooth5(progress) : 1 - smooth5(progress);
      if (kind === "lights-out") return { alpha: 1 - near, scale: 1, blur: 0 };
      if (kind === "flare-cut") return { scale: 1 + 0.03 * near, blur: 7 * near * near, alpha: 1 - 0.35 * near * near };
      return { alpha: 1, blur: 12 * near, scale: 1 + 0.015 * near };
    }
  }])
);
var resolveLumiereEnterDuration = (kind, startTime, endTime) => {
  const [min, max] = LUMIERE_TRANSITIONS[kind].enterClamp;
  return Math.max(min, Math.min(max, endTime - startTime));
};
var chooseLumiereTransition = (seed, paragraphIndex, previous) => {
  const choices = LUMIERE_TRANSITION_KINDS.filter((kind) => kind !== previous);
  let hash = 0;
  for (const char of `${seed}:${paragraphIndex}:transition`) hash = hash * 31 + char.charCodeAt(0) | 0;
  return choices[Math.abs(hash) % choices.length];
};

// folia:src/components/visualizer/pixiSceneCache.ts
var PixiSceneCache = class {
  constructor(hooks) {
    this.hooks = hooks;
  }
  scenes = /* @__PURE__ */ new Map();
  /**
   * Scenes the song handover replaced, waiting to be freed. Destroying a scene walks every
   * shot and every glyph's Text, and doing that for the whole cache on the frame the swap
   * lands is exactly the stall the wipe was supposed to hide. They are dropped one per frame
   * once the sweep is over instead.
   *
   * 换歌时换下来的场景，之后一帧销毁一个，免得交接那一帧卡住。
   */
  retired = [];
  get size() {
    return this.scenes.size;
  }
  /** 还有等着销毁的换下场景。 */
  get hasRetired() {
    return this.retired.length > 0;
  }
  has(index) {
    return this.scenes.has(index);
  }
  get(index) {
    return this.scenes.get(index);
  }
  forEach(callback) {
    this.scenes.forEach(callback);
  }
  /** 取缓存里的场景，没有就建；越界返回 null。 */
  ensure(index) {
    if (index < 0 || index >= this.hooks.count()) return null;
    const cached = this.scenes.get(index);
    if (cached) return cached;
    const scene = this.hooks.build(index);
    this.scenes.set(index, scene);
    return scene;
  }
  /** 收下一个在缓存外建好的场景（换歌交接的 staged）。 */
  adopt(index, scene) {
    this.scenes.set(index, scene);
  }
  /** 销毁离 index 超过一段、且不在 keep 里的场景。 */
  prune(index, keep) {
    this.scenes.forEach((scene, sceneIndex) => {
      if (Math.abs(sceneIndex - index) <= 1 || keep?.has(sceneIndex)) return;
      this.hooks.destroy(scene);
      this.scenes.delete(sceneIndex);
    });
  }
  /** 立即销毁全部缓存场景（不含已换下的）。 */
  clear() {
    this.scenes.forEach((scene) => this.hooks.destroy(scene));
    this.scenes.clear();
  }
  /** Transfer ownership without hiding or destroying a displayed scene. */
  takeAll() {
    const scenes = [...this.scenes.values()];
    this.scenes.clear();
    return scenes;
  }
  retireScenes(scenes) {
    scenes.forEach((scene) => {
      this.hooks.detach?.(scene);
      this.retired.push(scene);
    });
  }
  /** 整批换下：摘离场景层但不销毁，留给 drainRetired 一帧一个地释放。 */
  retireAll() {
    this.scenes.forEach((scene) => {
      this.hooks.detach?.(scene);
      this.retired.push(scene);
    });
    this.scenes.clear();
  }
  /**
   * 销毁一个换下的场景；没有可销毁的返回 false。
   *
   * Frees one retired scene. Called on frames that are not doing anything else expensive.
   */
  drainRetired() {
    const scene = this.retired.shift();
    if (scene === void 0) return false;
    this.hooks.destroy(scene);
    return true;
  }
  /** 运行时销毁：缓存与换下的场景全部释放。 */
  destroyAll() {
    this.clear();
    this.retired.forEach((scene) => this.hooks.destroy(scene));
    this.retired.length = 0;
  }
};

// folia:src/components/visualizer/pixi/pixiFilterPoolCompat.ts
var PATCHED = /* @__PURE__ */ Symbol.for("folia.pixi821FilterPoolCompat");
var installPixiFilterPoolCompat = (pixi) => {
  if (pixi.VERSION !== "8.21.0") return;
  const prototype = pixi.FilterSystem.prototype;
  if (prototype[PATCHED]) return;
  prototype[PATCHED] = true;
  const groups = /* @__PURE__ */ new Set();
  const pool = pixi.TexturePool;
  const unbindPassTextures = () => {
    const source = pixi.Texture.EMPTY.source;
    groups.forEach((group) => {
      group.setResource(source, 1);
      group.setResource(source.style, 2);
      group.setResource(source, 3);
    });
  };
  const init = prototype.init;
  prototype.init = function() {
    init?.call(this);
    groups.add(this._globalFilterBindGroup);
  };
  const destroy = prototype.destroy;
  prototype.destroy = function() {
    groups.delete(this._globalFilterBindGroup);
    this._globalFilterBindGroup.destroy();
    destroy.call(this);
  };
  const push = prototype.push;
  prototype.push = function(instruction) {
    const entry = this._filterStack[this._filterStackIndex];
    if (entry) entry.inputTexture = null;
    push.call(this, instruction);
  };
  const dropTextures = pool._dropTextures;
  pool._dropTextures = function(textures, shouldDestroy) {
    if (shouldDestroy && textures.length > 0) unbindPassTextures();
    dropTextures.call(this, textures, shouldDestroy);
  };
  const returnTexture = pool.returnTexture;
  pool.returnTexture = function(texture, resetStyle) {
    const key = this._poolKey[texture.uid];
    if (key !== void 0 && !this._buckets.has(key)) unbindPassTextures();
    returnTexture.call(this, texture, resetStyle);
  };
};

// folia:src/components/visualizer/pixi/loadPixi.ts
var loadPixi = async () => {
  const pixi = await import("./lib-JN454TPY.js");
  pixi.GlProgram.defaultOptions.preferredFragmentPrecision = "highp";
  installPixiFilterPoolCompat(pixi);
  return pixi;
};

// folia:src/components/visualizer/pixi/pixiProgramLinks.ts
var COMPLETION_STATUS_KHR = 37297;
var LOOK_EVERY_MS = 10;
var HAND_OVER_MS = 4;
var DECLARED_ATTRIBUTE = /^[ \t]*(?:attribute|in)[ \t]+(?:(?:lowp|mediump|highp)[ \t]+)?\w+[ \t]+(\w+)[ \t]*;/gm;
var programsOf = (pixi, renderer, stage2) => {
  const found = /* @__PURE__ */ new Map();
  const add = (shader) => {
    const program = shader?.glProgram;
    if (program && !found.has(program._key)) found.set(program._key, program);
  };
  let drawsGraphics = false;
  const walk = (node2) => {
    for (const filter of node2.filters ?? []) {
      add(filter);
      for (const field of Object.values(filter)) {
        for (const value of Array.isArray(field) ? field : [field]) {
          if (value instanceof pixi.Shader) add(value);
        }
      }
    }
    if (node2 instanceof pixi.Mesh) add(node2.shader);
    if (node2 instanceof pixi.Graphics) {
      if (node2.context.customShader) add(node2.context.customShader);
      else drawsGraphics = true;
    }
    node2.children.forEach(walk);
  };
  walk(stage2);
  add(new pixi.DefaultBatcher({ maxTextures: renderer.limits.maxBatchableTextures }).shader);
  if (drawsGraphics) add(renderer.renderPipes.graphics._adaptor.shader);
  if (renderer.backBuffer.useBackBuffer) add(renderer.backBuffer._bigTriangleShader);
  return [...found.values()];
};
var bindsAttributesInNameOrder = (program) => !/^[ \t]*#[ \t]*version[ \t]+300[ \t]+es[ \t]*$/m.test(program.vertex ?? "");
var byName = (a, b) => a > b ? 1 : -1;
var attributesInNameOrder = (gl, webGLProgram) => {
  const names = [];
  const count = gl.getProgramParameter(webGLProgram, gl.ACTIVE_ATTRIBUTES);
  for (let index = 0; index < count; index += 1) {
    const name = gl.getActiveAttrib(webGLProgram, index)?.name;
    if (name && !name.startsWith("gl_")) names.push(name);
  }
  names.sort(byName);
  if (names.every((name, location) => gl.getAttribLocation(webGLProgram, name) === location)) return true;
  names.forEach((name, location) => gl.bindAttribLocation(webGLProgram, location, name));
  gl.linkProgram(webGLProgram);
  return false;
};
var handOver = (pixi, gl, { program, webGLProgram, vertex: vertex2, fragment: fragment2 }) => {
  if (!gl.getProgramParameter(webGLProgram, gl.LINK_STATUS)) {
    pixi.logProgramError(gl, webGLProgram, vertex2, fragment2);
  }
  program._attributeData = pixi.extractAttributesFromGlProgram(webGLProgram, gl, false);
  program._uniformData = pixi.getUniformData(webGLProgram, gl);
  program._uniformBlockData = pixi.getUboData(webGLProgram, gl);
  gl.deleteShader(vertex2);
  gl.deleteShader(fragment2);
  const uniformData = {};
  for (const name in program._uniformData) {
    const data = program._uniformData[name];
    uniformData[name] = {
      location: gl.getUniformLocation(webGLProgram, name),
      value: pixi.defaultValue(data.type, data.size)
    };
  }
  return new pixi.GlProgramData(webGLProgram, uniformData);
};
var linkPixiPrograms = async (pixi, renderer, stage2, label, signal) => {
  if (pixi.VERSION !== "8.21.0" || renderer.type !== pixi.RendererType.WEBGL) return;
  const webgl = renderer;
  const gl = webgl.gl;
  if (!gl.getExtension("KHR_parallel_shader_compile")) {
    console.info(`[PixiPrograms] ${label}: no parallel shader linking here; programs link on first draw`);
    return;
  }
  const linked = webgl.shader._programDataHash;
  const started = performance.now();
  const pending = programsOf(pixi, webgl, stage2).filter((program) => !linked[program._key] && !program.transformFeedbackVaryings).map((program) => {
    const vertex2 = pixi.compileShader(gl, gl.VERTEX_SHADER, program.vertex ?? "");
    const fragment2 = pixi.compileShader(gl, gl.FRAGMENT_SHADER, program.fragment ?? "");
    const webGLProgram = gl.createProgram();
    gl.attachShader(webGLProgram, vertex2);
    gl.attachShader(webGLProgram, fragment2);
    if (bindsAttributesInNameOrder(program)) {
      const declared = [...(program.vertex ?? "").matchAll(DECLARED_ATTRIBUTE)].map((match) => match[1]).sort(byName);
      declared.forEach((name, location) => gl.bindAttribLocation(webGLProgram, location, name));
    }
    gl.linkProgram(webGLProgram);
    return { program, webGLProgram, vertex: vertex2, fragment: fragment2, rebound: false };
  });
  const count = pending.length;
  while (pending.length > 0) {
    await new Promise((resolve) => {
      window.setTimeout(resolve, LOOK_EVERY_MS);
    });
    if (signal?.aborted || gl.isContextLost()) return;
    const look = performance.now();
    while (pending.length > 0 && performance.now() - look < HAND_OVER_MS) {
      const next = pending[0];
      if (!gl.getProgramParameter(next.webGLProgram, COMPLETION_STATUS_KHR)) break;
      pending.shift();
      if (!next.rebound && bindsAttributesInNameOrder(next.program) && !attributesInNameOrder(gl, next.webGLProgram)) {
        pending.push({ ...next, rebound: true });
        continue;
      }
      linked[next.program._key] = handOver(pixi, gl, next);
    }
  }
  if (count > 0) console.info(`[PixiPrograms] ${label}: ${count} programs linked side by side in ${Math.round(performance.now() - started)} ms`);
};

// folia:src/components/visualizer/pixi/pixiWebGLContext.ts
var PIXI_EXTENSIONS = [
  "EXT_texture_filter_anisotropic",
  "OES_texture_float_linear",
  "WEBGL_compressed_texture_s3tc",
  "WEBGL_compressed_texture_s3tc_srgb",
  "WEBGL_compressed_texture_etc",
  "WEBGL_compressed_texture_etc1",
  "WEBGL_compressed_texture_pvrtc",
  "WEBKIT_WEBGL_compressed_texture_pvrtc",
  "WEBGL_compressed_texture_atc",
  "WEBGL_compressed_texture_astc",
  "EXT_texture_compression_bptc",
  "EXT_texture_compression_rgtc",
  "WEBGL_lose_context",
  "EXT_color_buffer_float",
  "WEBGL_provoking_vertex",
  // linkPixiPrograms asks for it next.
  "KHR_parallel_shader_compile"
];
var TASK_MS = 4;
var nextTask = () => new Promise((resolve) => {
  window.setTimeout(resolve);
});
var cancelled = () => new DOMException("Pixi context creation was cancelled", "AbortError");
var makePixiContext = async (pixi, options, signal) => {
  if (pixi.VERSION !== "8.21.0") return {};
  await nextTask();
  if (signal?.aborted) throw cancelled();
  const canvas = document.createElement("canvas");
  const context = canvas.getContext("webgl2", {
    alpha: (options.backgroundAlpha ?? 1) < 1,
    premultipliedAlpha: true,
    antialias: Boolean(options.antialias) && !options.useBackBuffer,
    stencil: true,
    preserveDrawingBuffer: false,
    powerPreference: options.powerPreference ?? "default"
  });
  if (!context) return {};
  let started = performance.now();
  for (const name of PIXI_EXTENSIONS) {
    if (performance.now() - started > TASK_MS) {
      await nextTask();
      if (signal?.aborted) {
        context.getExtension("WEBGL_lose_context")?.loseContext();
        throw cancelled();
      }
      started = performance.now();
    }
    context.getExtension(name);
  }
  return { canvas, context };
};

// folia:src/components/visualizer/lumiere/lumiereAudio.ts
var ATTACK_SECONDS = 0.06;
var RELEASE_SECONDS = 0.25;
var normalizeLumiereAudioValue = (value, rawScale) => {
  if (!Number.isFinite(value) || value <= 0) return 0;
  return Math.min(1, rawScale ? value / 255 : value);
};
var smoothLumiereAudioValue = (current, target, dt) => {
  const tau = target > current ? ATTACK_SECONDS : RELEASE_SECONDS;
  const k = 1 - Math.exp(-Math.max(0, dt) / tau);
  return current + (target - current) * k;
};
var createLumiereAudioSampler = (initial) => {
  let sources = initial;
  let rawScale = false;
  let lastMs = 0;
  const frame2 = { bass: 0, treble: 0, power: 0 };
  const read = (value) => {
    const raw = value?.get() ?? 0;
    if (raw > 1) rawScale = true;
    return raw;
  };
  return {
    frame: frame2,
    setSources: (next) => {
      if (next.audioPower === sources.audioPower && next.audioBands === sources.audioBands) return;
      sources = next;
      rawScale = false;
    },
    sample: (nowMs, paused) => {
      const dt = lastMs > 0 ? Math.min(0.1, (nowMs - lastMs) / 1e3) : 1;
      lastMs = nowMs;
      if (paused) {
        frame2.bass = 0;
        frame2.treble = 0;
        frame2.power = 0;
        return;
      }
      const bass = read(sources.audioBands.bass);
      const treble = read(sources.audioBands.treble);
      const power = read(sources.audioPower);
      frame2.bass = smoothLumiereAudioValue(frame2.bass, normalizeLumiereAudioValue(bass, rawScale), dt);
      frame2.treble = smoothLumiereAudioValue(frame2.treble, normalizeLumiereAudioValue(treble, rawScale), dt);
      frame2.power = smoothLumiereAudioValue(frame2.power, normalizeLumiereAudioValue(power, rawScale), dt);
    }
  };
};

// folia:src/utils/lyrics/renderHints.ts
var MICRO_LINE_DURATION_THRESHOLD = 0.1;
var SHORT_LINE_DURATION_THRESHOLD = 0.18;
var MICRO_LINE_RENDER_FLOOR = 0.067;
var getLastWordEndTime = (line2) => {
  const lastWord = line2.words?.[line2.words.length - 1];
  return lastWord?.endTime ?? line2.endTime;
};
var getLineTransitionTiming = (rawDuration, lineTransitionMode, wordRevealMode) => {
  if (lineTransitionMode === "none") {
    return {
      enterDuration: 0,
      exitDuration: 0,
      linePassHold: 0
    };
  }
  if (lineTransitionMode === "fast") {
    return {
      enterDuration: clamp(rawDuration * 0.45, 0.045, 0.06),
      exitDuration: clamp(rawDuration * 0.22, 0.03, 0.04),
      linePassHold: wordRevealMode === "instant" ? 0 : 0.03
    };
  }
  return {
    enterDuration: Math.min(0.42, Math.max(0.22, Math.max(rawDuration, 0.12) * 0.34)),
    exitDuration: Math.min(0.32, Math.max(0.18, Math.max(rawDuration, 0.12) * 0.18)),
    linePassHold: wordRevealMode === "instant" ? 0 : 0.06
  };
};
var getTimingClass = (rawDuration) => {
  if (rawDuration < MICRO_LINE_DURATION_THRESHOLD) {
    return "micro";
  }
  if (rawDuration < SHORT_LINE_DURATION_THRESHOLD) {
    return "short";
  }
  return "normal";
};
var getLineTransitionMode = (timingClass) => {
  if (timingClass === "micro") {
    return "none";
  }
  if (timingClass === "short") {
    return "fast";
  }
  return "normal";
};
var getWordRevealMode = (timingClass) => {
  if (timingClass === "micro") {
    return "instant";
  }
  if (timingClass === "short") {
    return "fast";
  }
  return "normal";
};
var clamp = (value, min, max) => Math.min(Math.max(value, min), max);
var buildLineRenderEndTime = (line2, rawDuration, lineTransitionMode, wordRevealMode) => {
  if (lineTransitionMode === "none") {
    return Math.max(line2.endTime, line2.startTime + MICRO_LINE_RENDER_FLOOR);
  }
  const transitionTiming = getLineTransitionTiming(rawDuration, lineTransitionMode, wordRevealMode);
  const linePassStart = Math.max(getLastWordEndTime(line2), line2.startTime) + transitionTiming.linePassHold;
  const exitStart = lineTransitionMode === "fast" ? Math.max(line2.startTime + transitionTiming.enterDuration + 0.01, linePassStart, line2.endTime - transitionTiming.exitDuration) : Math.max(linePassStart, line2.endTime - transitionTiming.exitDuration);
  return Math.max(line2.endTime, exitStart + transitionTiming.exitDuration);
};
function buildLineRenderHints(lineOrStart, endTime) {
  const line2 = typeof lineOrStart === "number" ? { startTime: lineOrStart, endTime: endTime ?? lineOrStart } : lineOrStart;
  const rawDuration = Math.max(line2.endTime - line2.startTime, 0);
  const timingClass = getTimingClass(rawDuration);
  const lineTransitionMode = getLineTransitionMode(timingClass);
  const wordRevealMode = getWordRevealMode(timingClass);
  return {
    rawDuration,
    timingClass,
    renderEndTime: buildLineRenderEndTime(line2, rawDuration, lineTransitionMode, wordRevealMode),
    lineTransitionMode,
    wordRevealMode
  };
}
var getLineRenderHints = (line2) => {
  if (!line2) {
    return null;
  }
  return line2.renderHints ?? buildLineRenderHints(line2);
};
var getLineRenderEndTime = (line2) => {
  if (!line2) {
    return Number.NEGATIVE_INFINITY;
  }
  return getLineRenderHints(line2)?.renderEndTime ?? line2.endTime;
};

// folia:src/components/visualizer/paragraphStructure.ts
var DEFAULT_PARAGRAPH_STRUCTURE_PARAMS = {
  gapMultiplier: 2.5,
  gapMin: 1.25,
  gapMax: 3.5,
  maxLines: 6,
  maxDuration: 18,
  recursiveSplit: true
};
var clamp2 = (value, min, max) => Math.min(max, Math.max(min, value));
var median = (values) => {
  if (values.length === 0) return 0.5;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? ((sorted[middle - 1] ?? sorted[middle]) + sorted[middle]) / 2 : sorted[middle];
};
var buildStructureLines = (lines) => lines.map((line2, sourceIndex) => ({
  sourceIndex,
  line: line2,
  renderEndTime: Math.max(
    line2.startTime,
    Math.min(getLineRenderEndTime(line2), lines[sourceIndex + 1]?.startTime ?? Number.POSITIVE_INFINITY)
  )
}));
var resolveParagraphGapThreshold = (lines, params = DEFAULT_PARAGRAPH_STRUCTURE_PARAMS) => {
  const gaps = lines.slice(1).map((line2, index) => line2.startTime - Math.min(getLineRenderEndTime(lines[index]), line2.startTime)).filter((gap) => gap > 0);
  return clamp2(median(gaps) * params.gapMultiplier, params.gapMin, params.gapMax);
};
var metadataChanged = (previous, next) => previous.blockIndex !== void 0 && next.blockIndex !== void 0 && previous.blockIndex !== next.blockIndex || previous.songPart !== void 0 && next.songPart !== void 0 && previous.songPart !== next.songPart;
var splitOversizedDraft = (draft, params) => {
  const output = [];
  let remaining = draft.lines;
  let boundary = draft.boundary;
  let loopGuard = 0;
  while (remaining.length > params.maxLines || remaining.length > 1 && remaining.at(-1).renderEndTime - remaining[0].line.startTime > params.maxDuration) {
    if (loopGuard++ > 1e3) break;
    const candidates = remaining.slice(2, -1).map((line2, offset) => ({
      splitIndex: offset + 2,
      gap: line2.line.startTime - remaining[offset + 1].renderEndTime
    }));
    const validCandidates = candidates.filter((candidate) => !Number.isNaN(candidate.gap));
    const rawSplitIndex = validCandidates.sort((a, b) => b.gap - a.gap)[0]?.splitIndex ?? Math.min(4, remaining.length - 1);
    const splitIndex = Math.max(1, rawSplitIndex);
    const head = { lines: remaining.slice(0, splitIndex), boundary };
    output.push(...params.recursiveSplit ? splitOversizedDraft(head, params) : [head]);
    remaining = remaining.slice(splitIndex);
    boundary = output.at(-1).lines.length >= params.maxLines ? "line-cap" : "duration-cap";
  }
  output.push({ lines: remaining, boundary });
  return output;
};
var draftParagraphs = (lines, threshold, params = DEFAULT_PARAGRAPH_STRUCTURE_PARAMS) => {
  const drafts = [];
  let current = { lines: [], boundary: "song-start" };
  lines.forEach((line2, index) => {
    const previous = lines[index - 1];
    const gap = previous ? line2.line.startTime - previous.renderEndTime : 0;
    const boundary = previous && metadataChanged(previous.line, line2.line) ? "metadata" : previous && gap >= threshold ? "time-gap" : null;
    if (boundary && current.lines.length > 0) {
      drafts.push(...splitOversizedDraft(current, params));
      current = { lines: [], boundary };
    }
    current.lines.push(line2);
  });
  if (current.lines.length > 0) drafts.push(...splitOversizedDraft(current, params));
  return drafts;
};
var countWordLike = (line2) => segmentLyricWords(line2).filter((part) => part.isWordLike).length;
var classifyParagraph = (lines, index, total) => {
  if (lines.some((item) => item.line.isChorus || /chorus|副歌/i.test(item.line.songPart ?? ""))) return "chorus";
  if (lines.some((item) => /bridge|break|間奏|ブリッジ/i.test(item.line.songPart ?? ""))) return "break";
  if (index === total - 1) return "outro";
  const duration = lines.at(-1).renderEndTime - lines[0].line.startTime;
  const segmentCount = lines.reduce((sum, line2) => sum + countWordLike(line2.line), 0);
  const punctuationCount = lines.reduce((sum, line2) => sum + (line2.line.fullText.match(/[!?！？…]/g)?.length ?? 0), 0);
  if (duration <= 3.5 || segmentCount <= 3) return "breath";
  if (punctuationCount >= 2 || segmentCount / Math.max(duration, 1) > 2.5) return "lift";
  return "verse";
};

// folia:src/components/visualizer/lumiere/lumiereSeamless.ts
var mergeLumiereParagraphs = (paragraphs) => {
  if (paragraphs.length < 2) return [...paragraphs];
  const first = paragraphs[0];
  const last = paragraphs.at(-1);
  const sections = paragraphs.map((paragraph) => ({
    startTime: paragraph.startTime,
    endTime: paragraph.endTime,
    kind: paragraph.kind
  }));
  return [{
    id: "lumiere-seamless",
    index: 0,
    kind: first.kind,
    boundary: first.boundary,
    startTime: first.startTime,
    endTime: last.endTime,
    lyricEndTime: last.lyricEndTime,
    lineIndices: paragraphs.flatMap((paragraph) => paragraph.lineIndices),
    lines: paragraphs.flatMap((paragraph) => paragraph.lines),
    shots: paragraphs.flatMap((paragraph) => paragraph.shots),
    transitionOut: null,
    opening: first.opening,
    sections
  }];
};

// folia:src/components/visualizer/lumiere/lumiereProgram.ts
var REOPEN_GAP = 2.5;
var INSTRUMENTAL_DURATION = 480;
var INSTRUMENTAL_PARAGRAPH = 32;
var BRIDGE_SHOT = 10;
var BRIDGE_SPLIT = 16;
var splitLongBridges = (shots) => shots.flatMap((shot) => {
  const length = shot.endTime - shot.startTime;
  if (!shot.isBridge || length <= BRIDGE_SPLIT) return [shot];
  const count = Math.max(2, Math.round(length / BRIDGE_SHOT));
  return Array.from({ length: count }, (_, index) => {
    const startTime = shot.startTime + length * index / count;
    const endTime = index === count - 1 ? shot.endTime : shot.startTime + length * (index + 1) / count;
    return { lines: [], startTime, endTime, lyricEndTime: endTime, isBridge: true };
  });
});
var planLyricParagraphs = (lines, params, duration) => {
  const structure = buildStructureLines(lines);
  const paragraphGapThreshold = resolveParagraphGapThreshold(lines);
  const drafts = draftParagraphs(structure, paragraphGapThreshold);
  const lyricEndTime = Math.max(...structure.map((line2) => line2.renderEndTime));
  const programEnd = Math.max(lyricEndTime, duration ?? 0);
  const firstStart = structure[0].line.startTime;
  const plans = [];
  const intro = firstStart >= params.bridgeGap;
  if (intro) {
    plans.push({ lines: [], kind: "break", boundary: "intro", startTime: 0, endTime: firstStart, lyricEndTime: firstStart });
  }
  drafts.forEach((draft, index) => {
    const next = drafts[index + 1];
    plans.push({
      lines: draft.lines,
      kind: classifyParagraph(draft.lines, index, drafts.length),
      boundary: draft.boundary,
      startTime: index === 0 && !intro ? Math.min(0, firstStart) : draft.lines[0].line.startTime,
      endTime: next ? next.lines[0].line.startTime : programEnd,
      lyricEndTime: draft.lines.at(-1).renderEndTime
    });
  });
  return { plans, paragraphGapThreshold, lyricEndTime, programEnd };
};
var planInstrumentalParagraphs = (duration) => {
  const count = Math.max(1, Math.round(duration / INSTRUMENTAL_PARAGRAPH));
  return Array.from({ length: count }, (_, index) => {
    const startTime = duration * index / count;
    const endTime = index === count - 1 ? duration : duration * (index + 1) / count;
    return { lines: [], kind: "break", boundary: index === 0 ? "song-start" : "instrumental", startTime, endTime, lyricEndTime: endTime };
  });
};
var compileLumiereProgram = (lines, seed, params = {}, options = {}) => {
  const resolvedParams = { ...DEFAULT_LUMIERE_PARAMS, ...params };
  const resolvedSeed = String(seed ?? "lumiere");
  const instrumental = lines.length === 0;
  const lyric = instrumental ? null : planLyricParagraphs(lines, resolvedParams, options.duration);
  const instrumentalDuration = Math.max(1, options.duration && options.duration > 0 ? options.duration : INSTRUMENTAL_DURATION);
  const plans = lyric ? lyric.plans : planInstrumentalParagraphs(instrumentalDuration);
  const chain = { recent: [], family: null };
  let previousTransition = null;
  const paragraphs = plans.map((plan, index) => {
    const planned = splitLongBridges(planShots(plan.lines, plan.startTime, plan.endTime, resolvedParams));
    const shots = planned.map((shot, shotIndex) => {
      const kind = castShot({
        seed: resolvedSeed,
        paragraphIndex: index,
        shotIndex,
        kind: plan.kind,
        isBridge: shot.isBridge,
        chain
      });
      advanceChain(chain, kind);
      return {
        id: `p${index}-lu${shotIndex}`,
        kind,
        lineIndices: shot.lines.map((line2) => line2.sourceIndex),
        startTime: shot.startTime,
        endTime: shot.endTime,
        lyricEndTime: shot.lyricEndTime,
        isBridge: shot.isBridge
      };
    });
    const next = plans[index + 1];
    let transitionOut = null;
    if (next) {
      const kind = chooseLumiereTransition(resolvedSeed, index, previousTransition);
      previousTransition = kind;
      const gap = next.startTime - plan.lyricEndTime;
      transitionOut = {
        kind,
        startTime: Math.max(plan.startTime, plan.endTime - LUMIERE_TRANSITIONS[kind].duration(gap)),
        endTime: plan.endTime
      };
    }
    const previous = plans[index - 1];
    const opening = !previous || plan.startTime - previous.lyricEndTime >= REOPEN_GAP;
    const lineIndices = plan.lines.map((line2) => line2.sourceIndex);
    return {
      id: `lumiere-p${index}`,
      index,
      kind: plan.kind,
      boundary: plan.boundary,
      startTime: plan.startTime,
      endTime: plan.endTime,
      lyricEndTime: plan.lyricEndTime,
      lineIndices,
      lines: lineIndices.map((lineIndex) => lines[lineIndex]),
      shots,
      transitionOut,
      opening
    };
  });
  return {
    version: 1,
    seed: resolvedSeed,
    instrumental,
    paragraphGapThreshold: lyric?.paragraphGapThreshold ?? 0,
    duration: lyric ? lyric.programEnd : instrumentalDuration,
    lyricEndTime: lyric ? lyric.lyricEndTime : null,
    paragraphs: options.seamless ? mergeLumiereParagraphs(paragraphs) : paragraphs
  };
};
var findLumiereParagraphIndexAtTime = (program, time) => {
  for (let index = program.paragraphs.length - 1; index >= 0; index -= 1) {
    if (time >= program.paragraphs[index].startTime) return index;
  }
  return 0;
};

// folia:src/utils/lyricRenderQuality.ts
var MAX_LYRIC_PIXEL_RATIO = 3;
var resolveLyricPixelRatio = (base, scale, max = MAX_LYRIC_PIXEL_RATIO) => {
  const safeBase = Number.isFinite(base) && base > 0 ? base : 1;
  const ratio = safeBase * scale;
  return scale > 1 ? Math.max(safeBase, Math.min(ratio, max)) : ratio;
};

// folia:src/components/visualizer/pixi/pixiTextureBudget.ts
var nextPow2 = (value) => {
  let v = value + (value === 0 ? 1 : 0);
  v -= 1;
  v |= v >>> 1;
  v |= v >>> 2;
  v |= v >>> 4;
  v |= v >>> 8;
  v |= v >>> 16;
  return v + 1;
};
var texturePoolAxis = (cssSize, resolution) => nextPow2(Math.ceil(cssSize * resolution - 1e-6));
var TEXTURE_POOL_MAX_RESOLUTION_DROP = 0.25;
var stepDownCandidate = (cssSize, resolution) => {
  const bucket = texturePoolAxis(cssSize, resolution);
  if (bucket < 2) return null;
  return bucket / 2 / cssSize;
};
var snapResolutionToTexturePool = (cssWidth, cssHeight, resolution, maxDrop = TEXTURE_POOL_MAX_RESOLUTION_DROP) => {
  if (![cssWidth, cssHeight, resolution].every((value) => Number.isFinite(value) && value > 0)) {
    return resolution;
  }
  const lowest = resolution * (1 - Math.min(Math.max(maxDrop, 0), 1));
  const candidates = [
    stepDownCandidate(cssWidth, resolution),
    stepDownCandidate(cssHeight, resolution)
  ].filter((candidate) => candidate !== null && candidate > 0 && candidate < resolution && candidate >= lowest);
  let best = resolution;
  let bestArea = texturePoolAxis(cssWidth, resolution) * texturePoolAxis(cssHeight, resolution);
  candidates.forEach((candidate) => {
    const area = texturePoolAxis(cssWidth, candidate) * texturePoolAxis(cssHeight, candidate);
    if (area >= bestArea) return;
    bestArea = area;
    best = candidate;
  });
  return best;
};

// folia:src/components/visualizer/lumiere/lumiereRuntimeTuning.ts
var LUMIERE_QUALITY_PROFILES = {
  full: { graphicsScale: 1, maxFogOctaves: 6, moteScale: 1 },
  balanced: { graphicsScale: 0.7, maxFogOctaves: 4, moteScale: 1 },
  low: { graphicsScale: 0.5, maxFogOctaves: 3, moteScale: 0.6 }
};
var LUMIERE_MAX_RENDER_RESOLUTION = 2;
var resolveLumiereRenderResolution = (devicePixelRatio) => {
  const ratio = typeof devicePixelRatio === "number" && Number.isFinite(devicePixelRatio) ? devicePixelRatio : 1;
  return Math.min(LUMIERE_MAX_RENDER_RESOLUTION, Math.max(1, ratio));
};
var resolveLumiereScaledRenderResolution = (devicePixelRatio, scale) => resolveLyricPixelRatio(resolveLumiereRenderResolution(devicePixelRatio), scale);
var resolveLumiereGraphicsResolution = (width, height, renderResolution, quality) => {
  const { graphicsScale } = LUMIERE_QUALITY_PROFILES[quality];
  if (graphicsScale >= 1) return renderResolution;
  return snapResolutionToTexturePool(width, height, renderResolution * graphicsScale);
};
var resolveLumiereBloomLevelDrop = (renderResolution, graphicsResolution) => graphicsResolution > 0 && graphicsResolution < renderResolution ? Math.max(0, Math.round(Math.log2(renderResolution / graphicsResolution))) : 0;
var toLumiereSceneTuning = (tuning, context) => {
  const profile = LUMIERE_QUALITY_PROFILES[tuning.renderQuality] ?? LUMIERE_QUALITY_PROFILES.full;
  return {
    lightIntensity: tuning.lightIntensity,
    audioResponse: tuning.audioResponse,
    fogDensity: tuning.fogDensity,
    darkField: tuning.darkField,
    moteAmount: tuning.moteAmount * profile.moteScale,
    bloom: tuning.bloom,
    textBloom: tuning.textBloom,
    unlitOpacity: tuning.unlitOpacity,
    windowNeighbors: tuning.windowNeighbors,
    decay: tuning.decay,
    echo: context.showText ? tuning.echo : 0,
    fogOctaves: Math.min(tuning.fogOctaves, profile.maxFogOctaves),
    lineArt: tuning.lineArt,
    frontBokeh: tuning.frontBokeh,
    trails: tuning.trails,
    hideTrails: tuning.hideTrails,
    overlayFrame: tuning.overlayFrame,
    textOnly: tuning.textOnly,
    keywordColors: tuning.keywordColors,
    themeIcons: tuning.themeIcons,
    themeColorMix: tuning.themeColorMix
  };
};
var crossesZero = (previous, next) => previous > 0 !== next > 0;
var requiresLumiereSceneRebuild = (previous, next) => previous.moteAmount !== next.moteAmount || previous.windowNeighbors !== next.windowNeighbors || previous.decay !== next.decay || previous.echo !== next.echo || previous.lineArt !== next.lineArt || previous.frontBokeh !== next.frontBokeh || previous.trails !== next.trails || previous.textOnly !== next.textOnly || previous.keywordColors !== next.keywordColors || previous.themeIcons !== next.themeIcons || previous.themeColorMix !== next.themeColorMix || crossesZero(previous.bloom, next.bloom) || crossesZero(previous.textBloom, next.textBloom);

// folia:src/components/visualizer/lumiere/lumiereSceneFrames.ts
var smooth6 = (value) => {
  const t = Math.min(1, Math.max(0, value));
  return t * t * (3 - 2 * t);
};
var exitFrameOf = (program, index, time) => {
  const out = program.paragraphs[index]?.transitionOut;
  if (!out || time < out.startTime) return { alpha: 1, scale: 1, blur: 0 };
  const progress = (time - out.startTime) / Math.max(out.endTime - out.startTime, 1e-3);
  const frame2 = LUMIERE_TRANSITIONS[out.kind].resolveFrame("exit", progress);
  return out.kind === "lights-out" ? { ...frame2, alpha: 1 } : frame2;
};
var resolveLumiereSceneFrames = (program, time, transitionsEnabled) => {
  if (program.paragraphs.length === 0) return { activeIndex: -1, layers: [] };
  const activeIndex = findLumiereParagraphIndexAtTime(program, time);
  if (!transitionsEnabled) {
    return { activeIndex, layers: [{ index: activeIndex, alpha: 1, scale: 1, blur: 0 }] };
  }
  const paragraph = program.paragraphs[activeIndex];
  const current = exitFrameOf(program, activeIndex, time);
  const layers = [];
  const previousOut = activeIndex > 0 ? program.paragraphs[activeIndex - 1].transitionOut : null;
  if (previousOut) {
    const enterDuration = resolveLumiereEnterDuration(previousOut.kind, previousOut.startTime, previousOut.endTime);
    const progress = (time - paragraph.startTime) / enterDuration;
    if (progress >= 0 && progress < 1) {
      const enter = LUMIERE_TRANSITIONS[previousOut.kind].resolveFrame("enter", progress);
      const weight = smooth6(progress);
      const peak = exitFrameOf(program, activeIndex - 1, previousOut.endTime);
      if (peak.alpha * (1 - weight) > 2e-3) {
        layers.push({ index: activeIndex - 1, alpha: peak.alpha * (1 - weight), scale: peak.scale, blur: peak.blur });
      }
      layers.push({
        index: activeIndex,
        alpha: Math.min(enter.alpha, weight) * current.alpha,
        scale: enter.scale * current.scale,
        blur: Math.max(enter.blur, current.blur)
      });
      return { activeIndex, layers };
    }
  }
  layers.push({ index: activeIndex, ...current });
  return { activeIndex, layers };
};

// folia:src/components/visualizer/lumiere/lumiereGroupFilters.ts
var isBloomFilter = (filter) => typeof filter.options?.strength === "number";
var bloomOf = (group) => (group.filters ?? []).find(isBloomFilter) ?? null;
var applyLumiereGroupQuality = (group, quality) => {
  const bloom2 = bloomOf(group);
  if (bloom2) {
    bloom2.options.strength = quality.preset.strength * quality.multiplier;
    bloom2.options.levels = Math.max(1, quality.preset.levels - quality.levelDrop);
    bloom2.resolution = quality.resolution ?? "inherit";
    return;
  }
  const { passthrough, resolution } = quality;
  if (!passthrough) return;
  const attached = (group.filters ?? []).includes(passthrough);
  if (resolution === null) {
    if (attached) group.filters = [];
    return;
  }
  passthrough.resolution = resolution;
  if (!attached) group.filters = [passthrough];
};
var detachLumierePassthrough = (group, passthrough) => {
  if (passthrough && (group.filters ?? []).includes(passthrough)) group.filters = [];
};

// folia:src/components/visualizer/lumiere/lumiereKernel.ts
var fromParams = ({ x, y, pivotX, pivotY, scale, rotation }) => {
  const cos = Math.cos(rotation) * scale;
  const sin = Math.sin(rotation) * scale;
  return { a: cos, b: sin, c: -sin, d: cos, tx: x - (cos * pivotX - sin * pivotY), ty: y - (sin * pivotX + cos * pivotY) };
};
var multiply = (m, n) => ({
  a: m.a * n.a + m.c * n.b,
  b: m.b * n.a + m.d * n.b,
  c: m.a * n.c + m.c * n.d,
  d: m.b * n.c + m.d * n.d,
  tx: m.a * n.tx + m.c * n.ty + m.tx,
  ty: m.b * n.tx + m.d * n.ty + m.ty
});
var invert = (m) => {
  const det = m.a * m.d - m.b * m.c || 1e-12;
  return {
    a: m.d / det,
    b: -m.b / det,
    c: -m.c / det,
    d: m.a / det,
    tx: (m.c * m.ty - m.d * m.tx) / det,
    ty: (m.b * m.tx - m.a * m.ty) / det
  };
};
var cameraBetween = (rest, current) => multiply(fromParams(current), invert(fromParams(rest)));

// folia:src/components/visualizer/lumiere/lumiereUnit.ts
var buildLumiereSceneShots = (paragraph) => {
  const localLine = new Map(paragraph.lineIndices.map((lineIndex, index) => [lineIndex, index]));
  const shots = paragraph.shots.map((shot) => ({
    profile: profileOf(shot.kind),
    startTime: shot.startTime,
    endTime: shot.endTime,
    lines: shot.lineIndices.map((index) => localLine.get(index)).filter((index) => index !== void 0)
  }));
  if (shots.length === 0) {
    shots.push({ profile: profileOf(""), startTime: paragraph.startTime, endTime: paragraph.endTime, lines: [] });
  }
  return shots;
};
var createLumiereUnit = (pixi, options) => {
  const { paragraph } = options;
  const scene = createLumiereScene(pixi, {
    width: options.width,
    height: options.height,
    resolution: options.resolution,
    seed: `${options.programSeed}:${paragraph.id}`,
    theme: options.theme,
    tuning: options.tuning,
    lines: paragraph.lines,
    shots: buildLumiereSceneShots(paragraph),
    startTime: paragraph.startTime,
    endTime: paragraph.endTime,
    sprites: options.sprites,
    opening: paragraph.opening,
    fadeOut: paragraph.transitionOut?.kind === "lights-out" ? { start: paragraph.transitionOut.startTime, end: paragraph.transitionOut.endTime } : null,
    audioAt: options.audioAt,
    tfnArrivalElapsed: options.tfnArrivalElapsed,
    typography: options.typography,
    sections: paragraph.sections
  });
  const shotAt = (time) => {
    let found = paragraph.shots[0];
    for (const shot of paragraph.shots) if (shot.startTime <= time) found = shot;
    return found;
  };
  return {
    paragraph,
    scene,
    update: (time) => scene.update(time),
    cameraMatrix: (time) => cameraBetween(scene.rest, scene.camera(time)),
    shotAt,
    destroy: () => scene.destroy()
  };
};

// folia:src/components/visualizer/lumiere/lumiereSceneEntry.ts
var BLUR_EPSILON = 0.3;
var applyLumiereSceneQuality = (groups, quality) => {
  applyLumiereGroupQuality(groups.graphics, {
    preset: LUMIERE_BLOOM.graphics,
    multiplier: quality.bloom,
    resolution: quality.graphicsResolution,
    levelDrop: quality.bloomLevelDrop,
    passthrough: quality.passthrough
  });
  applyLumiereGroupQuality(groups.text, {
    preset: LUMIERE_BLOOM.text,
    multiplier: quality.textBloom,
    resolution: null,
    levelDrop: 0,
    passthrough: null
  });
};
var buildLumiereSceneEntry = (pixi, context, index) => {
  const { width, height } = context;
  const unit = createLumiereUnit(pixi, {
    paragraph: context.program.paragraphs[index],
    width,
    height,
    resolution: context.resolution,
    programSeed: context.program.seed,
    theme: context.theme,
    tuning: context.tuning,
    sprites: context.sprites,
    audioAt: context.audioAt,
    tfnArrivalElapsed: context.tfnArrivalElapsed
  });
  unit.scene.text.visible = context.showText;
  applyLumiereSceneQuality(unit.scene, context.quality);
  const holder = new pixi.Container();
  holder.addChild(unit.scene.view);
  holder.pivot.set(width / 2, height / 2);
  holder.position.set(width / 2, height / 2);
  holder.zIndex = index;
  return { index, unit, holder, blur: null };
};
var applyLumiereLayerFrame = (pixi, entry, frame2, blurResolution) => {
  entry.holder.alpha = frame2.alpha;
  entry.holder.scale.set(frame2.scale);
  if (frame2.blur > BLUR_EPSILON) {
    if (!entry.blur) {
      entry.blur = new pixi.BlurFilter({ strength: frame2.blur, quality: 3, resolution: blurResolution });
    }
    entry.blur.strength = frame2.blur;
    if (!entry.holder.filters?.includes(entry.blur)) entry.holder.filters = [entry.blur];
  } else if (entry.holder.filters?.length) {
    entry.holder.filters = [];
  }
};
var destroyLumiereSceneEntry = (entry, passthrough) => {
  entry.holder.parent?.removeChild(entry.holder);
  entry.holder.filters = [];
  entry.blur?.destroy();
  entry.blur = null;
  detachLumierePassthrough(entry.unit.scene.graphics, passthrough);
  entry.holder.removeChild(entry.unit.scene.view);
  entry.unit.destroy();
  entry.holder.destroy();
};

// folia:src/components/visualizer/lumiere/credits.ts
var lumiereScaleMask18 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET18 = (15875 ^ lumiereScaleMask18) + Math.imul(15230 ^ lumiereScaleMask18, 10553 ^ lumiereScaleMask18) - ((15875 ^ lumiereScaleMask18) + Math.imul(15230 ^ lumiereScaleMask18, 10553 ^ lumiereScaleMask18));
var smooth7 = (value) => {
  const t = Math.min(1, Math.max(0, value));
  return t * t * (3 - 2 * t);
};
var TITLE_START = 1.5 + LUMIERE_NEUTRAL_OFFSET18;
var TITLE_SPAN = 2.4;
var TITLE_STEP = 0.14;
var resolveLumiereCreditsFrame = (time, finalEndTime) => {
  const elapsed = time - finalEndTime;
  if (elapsed <= 0) return { active: false, lyricAlpha: 1, lyricBlur: 0, posterAlpha: 0, posterOffsetY: 0, posterScale: 0.985 };
  const exit = smooth7(elapsed / 1.6);
  const enter = smooth7((elapsed - 0.5) / 1.4);
  return {
    active: true,
    lyricAlpha: 1 - exit,
    lyricBlur: exit * 10,
    posterAlpha: enter,
    posterOffsetY: 0,
    posterScale: 0.985 + 0.015 * enter
  };
};
var clean = (value) => value?.trim() ?? "";
var hasLumiereCredits = (metadata) => Boolean(clean(metadata.title) || clean(metadata.artist) || clean(metadata.album));
var titleLine = (title) => {
  const chars = Array.from(title);
  const step = Math.min(TITLE_STEP, TITLE_SPAN / Math.max(chars.length, 1));
  return {
    fullText: title,
    startTime: TITLE_START,
    endTime: TITLE_START + step * chars.length + 0.6,
    words: chars.map((text, i) => ({ text, startTime: TITLE_START + i * step, endTime: TITLE_START + (i + 1) * step }))
  };
};
var createLumiereCredits = (pixi, options) => {
  const { width, height, tuning, sprites, theme } = options;
  const aspect = width / height;
  const palette = resolveLumierePalette(theme, tuning.themeColorMix);
  const lightHex = hexOf(palette.light);
  const title = clean(options.metadata.title);
  const artist = clean(options.metadata.artist);
  const album = clean(options.metadata.album);
  const random = createRng("lumiere:credits");
  const rig2 = {
    beams: [
      shaft({ spread: 0.1, width: 0.06, length: 0.9, intensity: 0.85 }),
      shaft({ spread: 0.3, width: 0.1, length: 0.6, softness: 0.9, intensity: 0.22, streaks: 0.85, streakFreq: 26, core: 0.3 })
    ],
    fog: { ...FOG, density: 0.9 },
    glare: { ...GLARE, intensity: 0.8 }
  };
  const view = new pixi.Container();
  const graphics = new pixi.Container();
  const field = createLightField(pixi, width, height);
  const art = createLineArt(pixi, {
    height,
    spec: mergeSpecs(
      protractorHalo({ cx: aspect * 0.5, cy: 0.03, radius: 0.3, alpha: 0.55 }),
      viewfinderFrame({ aspect, left: 0.16, top: 0.27, right: 0.84, bottom: 0.7, delay: 0.1, alpha: 0.32 }),
      scatteredSparks({ aspect, count: 14, random, delay: 0.3 })
    ),
    starTexture: sprites.star
  });
  art.view.visible = tuning.lineArt;
  const motes = createMotes(pixi, {
    width,
    height,
    seed: "lumiere:credits:motes",
    texture: sprites.dot,
    spec: { ...MOTES, count: Math.round(MOTES.count * tuning.moteAmount) }
  });
  graphics.addChild(field.view, art.view, motes.view);
  graphics.filterArea = new pixi.Rectangle(0, 0, width, height);
  const text = new pixi.Container();
  const font = resolveThemeFontStack(theme);
  const window2 = title ? createLyricWindow(pixi, {
    width,
    height,
    lines: [titleLine(title)],
    font,
    weight: resolveThemeFontWeight(theme, 600),
    resolution: options.resolution,
    region: { cx: 0.5 * aspect, cy: 0.49, w: 0.6 * aspect, h: 0.2 },
    heroPx: 0.1 * height,
    neighbors: 1,
    typography: "horizontal",
    decay: { strength: 0, delay: 1 },
    drift: 0,
    seed: "lumiere:credits:title",
    sprites,
    letterSpacing: 0.06
  }) : null;
  if (window2) text.addChild(window2.view);
  const detailStyle = (size, color, spacing) => new pixi.TextStyle({
    fontFamily: font,
    fontWeight: String(resolveThemeFontWeight(theme, 500)),
    fontSize: size,
    fill: hexOf(color),
    letterSpacing: size * spacing,
    align: "center",
    wordWrap: true,
    wordWrapWidth: width * 0.6
  });
  const detailSize = Math.max(13, height * 0.028);
  const details = [
    artist ? { text: artist.toLocaleUpperCase(), y: 0.35, size: detailSize, spacing: 0.32, color: palette.lit, delay: 0.9 } : null,
    album ? { text: album, y: 0.65, size: detailSize * 0.85, spacing: 0.16, color: palette.unlit, delay: 1.2 } : null
  ].filter((item) => item !== null).map((item) => {
    const label = new pixi.Text({ text: item.text, style: detailStyle(item.size, item.color, item.spacing), resolution: options.resolution });
    label.anchor.set(0.5);
    label.position.set(width / 2, item.y * height);
    label.alpha = 0;
    text.addChild(label);
    return { label, delay: item.delay + (title ? TITLE_START + Math.min(TITLE_SPAN, TITLE_STEP * Array.from(title).length) - 0.6 : 0) };
  });
  view.addChild(graphics, text);
  const graphicsBloom = createBloomFilter(pixi, { ...LUMIERE_BLOOM.graphics, strength: LUMIERE_BLOOM.graphics.strength * tuning.bloom, padding: 0, tint: [1, 1, 1] });
  const textBloom = createBloomFilter(pixi, { ...LUMIERE_BLOOM.text, strength: LUMIERE_BLOOM.text.strength * tuning.textBloom, padding: 0, tint: [1, 1, 1] });
  text.filterArea = new pixi.Rectangle(-width, -height, width * 3, height * 3);
  graphics.filters = tuning.bloom > 0 ? [graphicsBloom] : [];
  text.filters = tuning.textBloom > 0 ? [textBloom] : [];
  graphics.renderable = !tuning.textOnly;
  const update = (elapsed) => {
    const time = Math.max(0, elapsed);
    const rise = smooth7((time - 0.6) / 1.6);
    const ignite = time >= 0.9 ? 1.2 * Math.exp(-(time - 0.9) / 0.4) : 0;
    const beams = resolveBeams(rig2, time, aspect, { intensity: rise * tuning.lightIntensity, bass: 0, color: palette.light, local: time });
    if (!tuning.textOnly) {
      field.update({
        beams,
        rig: rig2,
        time,
        fogScale: tuning.fogDensity,
        color: palette.light,
        glareScale: rise * tuning.lightIntensity * (1 + ignite),
        dark: LUMIERE_SHADER_NO_DARK,
        octaves: tuning.fogOctaves
      });
      const draw = (time - 0.8) / 3.6;
      art.view.visible = tuning.lineArt && draw > 0;
      if (art.view.visible) art.update(time, draw, smooth7((time - 0.8) / 1.2), beams, lightHex);
      motes.update(time, beams, lightHex, rise);
    }
    window2?.update({
      time,
      beams,
      litColor: palette.lit,
      unlitColor: palette.unlit,
      unlitAlpha: tuning.unlitOpacity,
      hideTrails: tuning.hideTrails,
      intensity: smooth7((time - 0.4) / 0.8)
    });
    details.forEach(({ label, delay }) => {
      label.alpha = smooth7((time - delay) / 1.4) * 0.9;
    });
  };
  update(0);
  return {
    view,
    graphics,
    text,
    update,
    destroy: () => {
      graphics.filters = [];
      text.filters = [];
      graphicsBloom.destroy();
      textBloom.destroy();
      field.destroy();
      art.destroy();
      motes.destroy();
      window2?.destroy();
      view.destroy({ children: true });
    }
  };
};

// folia:src/components/visualizer/lumiere/lumiereCreditsLayer.ts
var PREBUILD_SECONDS = 4;
var INACTIVE = { active: false, lyricAlpha: 1, lyricBlur: 0, posterAlpha: 0, posterOffsetY: 0, posterScale: 1 };
var toSongMetadata = (metadata) => ({
  title: metadata.title ?? null,
  artist: metadata.artist ?? null,
  album: metadata.album ?? null
});
var LumiereCreditsLayer = class {
  constructor(pixi, sprites) {
    this.pixi = pixi;
    this.sprites = sprites;
    this.holder = new pixi.Container();
    this.holder.visible = false;
  }
  holder;
  credits = null;
  lyricEndTime = 0;
  get built() {
    return this.credits !== null;
  }
  hasMetadata(metadata) {
    return hasLumiereCredits(toSongMetadata(metadata));
  }
  /** 片尾时间线帧；没有片尾卡时恒为 inactive（歌词不淡出）。 */
  resolveFrame(time, program, metadata) {
    if (program.lyricEndTime === null || !this.hasMetadata(metadata)) return INACTIVE;
    this.lyricEndTime = program.lyricEndTime;
    return resolveLumiereCreditsFrame(time, program.lyricEndTime);
  }
  needsBuild(time, program, metadata) {
    return !this.credits && program.lyricEndTime !== null && time >= program.lyricEndTime - PREBUILD_SECONDS && this.hasMetadata(metadata);
  }
  build(context) {
    this.invalidate();
    this.credits = createLumiereCredits(this.pixi, {
      width: context.width,
      height: context.height,
      resolution: context.resolution,
      theme: context.theme,
      metadata: toSongMetadata(context.metadata),
      tuning: context.tuning,
      sprites: this.sprites
    });
    applyLumiereSceneQuality(this.credits, context.quality);
    this.holder.addChild(this.credits.view);
    this.holder.pivot.set(context.width / 2, context.height / 2);
  }
  applyQuality(quality) {
    if (this.credits) applyLumiereSceneQuality(this.credits, quality);
  }
  /** 片尾卡以画面中心缩放、上下偏移；没激活时整层不画。 */
  update(time, frame2, width, height) {
    const credits = this.credits;
    this.holder.visible = Boolean(credits) && frame2.active && frame2.posterAlpha > 2e-3;
    if (!credits || !this.holder.visible) return;
    this.holder.alpha = frame2.posterAlpha;
    this.holder.position.set(width / 2, height / 2 + frame2.posterOffsetY * height);
    this.holder.scale.set(frame2.posterScale);
    credits.update(time - this.lyricEndTime);
  }
  /** 作废当前片尾卡（下次需要时重建）。 */
  invalidate() {
    if (!this.credits) return;
    const credits = this.credits;
    this.credits = null;
    this.holder.removeChild(credits.view);
    credits.graphics.filters = [];
    credits.destroy();
    this.holder.visible = false;
  }
  destroy() {
    this.invalidate();
    this.holder.destroy({ children: true });
  }
};

// folia:src/components/visualizer/lumiere/lumiereDarkField.ts
var BRIGHT_BACKGROUND_LUMINANCE = 0.18;
var LUMIERE_BRIGHT_DARK_FIELD_FLOOR = 0.94;
var DARK_FIELD_SHADE = 0.06;
var resolveLumiereDarkField = (theme, darkField) => {
  const background = rgbOf(theme.backgroundColor, [0, 0, 0]);
  const strength = Number.isFinite(darkField) ? Math.min(1, Math.max(0, darkField)) : 0;
  const bright = luminance(background) > BRIGHT_BACKGROUND_LUMINANCE;
  return {
    color: scaleRgb(background, DARK_FIELD_SHADE),
    alpha: bright ? Math.max(strength, LUMIERE_BRIGHT_DARK_FIELD_FLOOR) : strength
  };
};
var LumiereDarkFieldLayer = class {
  view;
  sprite;
  theme = null;
  darkField = Number.NaN;
  width = 0;
  height = 0;
  constructor(pixi) {
    this.sprite = new pixi.Sprite(pixi.Texture.WHITE);
    this.sprite.visible = false;
    this.view = this.sprite;
  }
  update(theme, darkField, width, height) {
    if (theme !== this.theme || darkField !== this.darkField) {
      this.theme = theme;
      this.darkField = darkField;
      const field = resolveLumiereDarkField(theme, darkField);
      this.sprite.tint = hexOf(field.color);
      this.sprite.alpha = field.alpha;
      this.sprite.visible = field.alpha > 2e-3;
    }
    if (width !== this.width || height !== this.height) {
      this.width = width;
      this.height = height;
      this.sprite.setSize(width, height);
    }
  }
  destroy() {
    this.sprite.destroy();
  }
};

// folia:src/components/visualizer/pixiSongSwap.ts
var PixiSongSwap = class {
  constructor(hooks) {
    this.hooks = hooks;
  }
  pending = null;
  get active() {
    return this.pending !== null;
  }
  /** 正在交接的新歌（还没切过去）。 */
  get song() {
    return this.pending?.song ?? null;
  }
  /** 已经建好、还没切过去的场景（tuning / 尺寸变化时需要一起更新或丢弃）。 */
  get staged() {
    return this.pending?.staged ?? null;
  }
  /** 丢掉已建好的 staged（它是按旧的尺寸 / tuning 建的）；交接照常在下一帧切，切的时候重建。 */
  dropStaged() {
    const pending = this.pending;
    if (!pending?.staged) return;
    this.hooks.discard(pending.staged);
    pending.staged = null;
  }
  /** 开始一次交接，两帧之后 resolve。 */
  begin(song, signal) {
    return new Promise((resolve) => {
      const onAbort = () => this.settle(true);
      this.pending = {
        song,
        staged: null,
        prepared: false,
        settle: resolve,
        detachAbort: () => signal?.removeEventListener("abort", onAbort)
      };
      signal?.addEventListener("abort", onAbort, { once: true });
    });
  }
  /**
   * 每帧开头调用：第一帧 stage，第二帧 commit。
   *
   * One frame of the handover. First frame builds the incoming scene while the outgoing song
   * still holds the picture; second frame cuts to it. Nothing is drawn over the change - the
   * point is that the cut costs no work, not that it is hidden.
   */
  advance() {
    const pending = this.pending;
    if (!pending) return;
    if (!pending.prepared) {
      pending.prepared = true;
      pending.staged = this.hooks.stage(pending.song);
      return;
    }
    this.settle(true);
  }
  /**
   * 立即了结：commit 为 false（运行时正在销毁）时只丢弃 staged。
   *
   * Finishes an in-flight handover immediately, committing whatever it was still holding.
   */
  settle(commit) {
    const pending = this.pending;
    if (!pending) return;
    this.pending = null;
    pending.detachAbort();
    if (commit) this.hooks.commit(pending.song, pending.staged);
    else if (pending.staged) this.hooks.discard(pending.staged);
    pending.settle();
  }
};

// folia:src/components/visualizer/lumiere/overlay.ts
var lumiereScaleMask19 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET19 = (2401607263 ^ lumiereScaleMask19) + Math.imul(3848464964 ^ lumiereScaleMask19, 523 ^ lumiereScaleMask19) - ((2401607263 ^ lumiereScaleMask19) + Math.imul(3848464964 ^ lumiereScaleMask19, 523 ^ lumiereScaleMask19));
var buildLumiereOverlay = (pixi, options) => {
  const { width, height, theme } = options;
  const container = new pixi.Container();
  const g = new pixi.Graphics();
  const color = hexOf(resolveLumierePalette(theme, options.themeColorMix ?? 0).light);
  const unit = Math.min(width, height);
  const { padX, padY } = frameInsets(width, height);
  const arm = unit * (0.045 + LUMIERE_NEUTRAL_OFFSET19);
  const line2 = Math.max(1.2, unit / 600);
  const alpha = 0.5;
  for (const [x, y, sx, sy] of [[padX, padY, 1, 1], [width - padX, padY, -1, 1], [width - padX, height - padY, -1, -1], [padX, height - padY, 1, -1]]) {
    g.moveTo(x, y + sy * arm).lineTo(x, y).lineTo(x + sx * arm, y).stroke({ color, width: line2, alpha });
  }
  const mark = unit * 0.012;
  for (const x of [padX, width - padX]) {
    const y = height / 2;
    g.circle(x, y, mark * 0.6).stroke({ color, width: line2, alpha: alpha * 0.8 });
    g.moveTo(x - mark, y).lineTo(x + mark, y).stroke({ color, width: line2, alpha: alpha * 0.8 });
    g.moveTo(x, y - mark).lineTo(x, y + mark).stroke({ color, width: line2, alpha: alpha * 0.8 });
  }
  const dashY = padY;
  for (const side of [-1, 1]) {
    for (let k = 0; k < 4; k += 1) {
      const x = width / 2 + side * (unit * 0.1 + k * unit * 0.018);
      g.moveTo(x, dashY).lineTo(x + side * unit * 9e-3, dashY).stroke({ color, width: line2, alpha: alpha * 0.55 });
    }
  }
  container.addChild(g);
  return container;
};

// folia:src/components/visualizer/lumiere/light/sprites.ts
var lumiereScaleMask20 = globalThis.devicePixelRatio | 0;
var LUMIERE_NEUTRAL_OFFSET20 = (306 ^ lumiereScaleMask20) + Math.imul(337 ^ lumiereScaleMask20, 454 ^ lumiereScaleMask20) - ((306 ^ lumiereScaleMask20) + Math.imul(337 ^ lumiereScaleMask20, 454 ^ lumiereScaleMask20));
var canvasOf = (width, height) => {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  return { canvas, context: canvas.getContext("2d") };
};
var drawDot = (size) => {
  const { canvas, context } = canvasOf(size, size);
  const r = size / (2 + LUMIERE_NEUTRAL_OFFSET20);
  const gradient = context.createRadialGradient(r, r, 0, r, r, r);
  gradient.addColorStop(0, "rgba(255,255,255,1)");
  gradient.addColorStop(0.18, "rgba(255,255,255,0.72)");
  gradient.addColorStop(0.45, "rgba(255,255,255,0.2)");
  gradient.addColorStop(1, "rgba(255,255,255,0)");
  context.fillStyle = gradient;
  context.fillRect(0, 0, size, size);
  return canvas;
};
var drawStar = (size) => {
  const { canvas, context } = canvasOf(size, size);
  const r = size / 2;
  const halo = context.createRadialGradient(r, r, 0, r, r, r * 0.5);
  halo.addColorStop(0, "rgba(255,255,255,1)");
  halo.addColorStop(0.12, "rgba(255,255,255,0.8)");
  halo.addColorStop(0.4, "rgba(255,255,255,0.14)");
  halo.addColorStop(1, "rgba(255,255,255,0)");
  context.fillStyle = halo;
  context.fillRect(0, 0, size, size);
  context.globalCompositeOperation = "lighter";
  const ray2 = (angle, length, thickness, alpha) => {
    context.save();
    context.translate(r, r);
    context.rotate(angle);
    const gradient = context.createLinearGradient(0, 0, length, 0);
    gradient.addColorStop(0, `rgba(255,255,255,${alpha})`);
    gradient.addColorStop(1, "rgba(255,255,255,0)");
    context.fillStyle = gradient;
    context.beginPath();
    context.moveTo(0, -thickness);
    context.lineTo(length, 0);
    context.lineTo(0, thickness);
    context.closePath();
    context.fill();
    context.restore();
  };
  for (let i = 0; i < 4; i += 1) ray2(Math.PI / 2 * i, r * 0.98, size * 0.018, 0.95);
  for (let i = 0; i < 4; i += 1) ray2(Math.PI / 2 * i + Math.PI / 4, r * 0.42, size * 0.01, 0.45);
  return canvas;
};
var drawBokeh = (size) => {
  const { canvas, context } = canvasOf(size, size);
  const r = size / 2;
  const gradient = context.createRadialGradient(r, r, 0, r, r, r * 0.96);
  gradient.addColorStop(0, "rgba(255,255,255,0.35)");
  gradient.addColorStop(0.78, "rgba(255,255,255,0.42)");
  gradient.addColorStop(0.9, "rgba(255,255,255,0.75)");
  gradient.addColorStop(1, "rgba(255,255,255,0)");
  context.fillStyle = gradient;
  context.beginPath();
  context.arc(r, r, r * 0.96, 0, Math.PI * 2);
  context.fill();
  return canvas;
};
var drawStreak = (width, height) => {
  const { canvas, context } = canvasOf(width, height);
  const horizontal = context.createLinearGradient(0, 0, width, 0);
  horizontal.addColorStop(0, "rgba(255,255,255,0)");
  horizontal.addColorStop(0.5, "rgba(255,255,255,1)");
  horizontal.addColorStop(1, "rgba(255,255,255,0)");
  context.fillStyle = horizontal;
  context.fillRect(0, 0, width, height);
  context.globalCompositeOperation = "destination-in";
  const vertical = context.createLinearGradient(0, 0, 0, height);
  vertical.addColorStop(0, "rgba(255,255,255,0)");
  vertical.addColorStop(0.5, "rgba(255,255,255,1)");
  vertical.addColorStop(1, "rgba(255,255,255,0)");
  context.fillStyle = vertical;
  context.fillRect(0, 0, width, height);
  return canvas;
};
var createLightSprites = (pixi) => {
  const textures = {
    dot: pixi.Texture.from(drawDot(128)),
    star: pixi.Texture.from(drawStar(256)),
    bokeh: pixi.Texture.from(drawBokeh(128)),
    streak: pixi.Texture.from(drawStreak(512, 32))
  };
  return {
    ...textures,
    destroy: () => Object.values(textures).forEach((texture) => texture.destroy(true))
  };
};

// folia:src/components/visualizer/lumiere/createLumierePixiRuntime.ts
var REBUILD_DEBOUNCE_MS = 220;
var MIN_WIDTH = 320;
var MIN_HEIGHT = 240;
const sameTfnTrack = (a, b) => (a.trackIdentity ?? a.seed) === (b.trackIdentity ?? b.seed);
class TfnPixiSceneHandoff {
  tfnLastSceneTime = null;
  tfnLastSceneTop = 0;
  tfnSceneHandoff = null;
  tfnRetainScenes() {
    if (this.tfnSceneHandoff || this.options.paused || this.options.staticMode || !this.app.canvas?.isConnected || !this.sceneCache.size) return;
    const entries = this.sceneCache.takeAll();
    const visible = entries.filter((entry) => entry.holder.visible && entry.holder.alpha > 2e-3);
    this.sceneCache.retireScenes(entries.filter((entry) => !visible.includes(entry)));
    if (!visible.length) return;
    let resolve;
    const finished = new Promise((done) => {
      resolve = done;
    });
    this.tfnSceneHandoff = {
      entries: visible.map((entry) => ({ entry, alpha: entry.holder.alpha, y: (entry.holder.y ?? 0) + this.tfnLastSceneTop - (this.sceneLayer?.y ?? 0) })),
      parentY: this.sceneLayer?.y ?? 0,
      at: null,
      time: this.tfnLastSceneTime ?? this.options.currentTime.get(),
      theme: this.options.song.theme,
      finished,
      resolve
    };
  }
  tfnFinishSceneHandoff() {
    const handoff = this.tfnSceneHandoff;
    if (!handoff) return;
    this.tfnSceneHandoff = null;
    this.sceneCache.retireScenes(handoff.entries.map((item) => item.entry));
    handoff.resolve();
  }
  tfnSceneMix() {
    const handoff = this.tfnSceneHandoff;
    if (!handoff) return 1;
    if (this.options.paused || this.options.staticMode) {
      this.tfnFinishSceneHandoff();
      return 1;
    }
    handoff.at ??= performance.now();
    const progress = (performance.now() - handoff.at) / (HANDOFF * 1e3);
    if (progress >= 1) {
      this.tfnFinishSceneHandoff();
      return 1;
    }
    return LUMIERE_TRANSITIONS["lights-out"].resolveFrame("enter", progress).alpha;
  }
  tfnRenderOutgoing(mix) {
    const handoff = this.tfnSceneHandoff;
    if (!handoff || handoff.at === null) return;
    const time = handoff.time + Math.max(0, performance.now() - handoff.at) / 1e3;
    for (const { entry, alpha, y } of handoff.entries) {
      entry.holder.y = y + handoff.parentY - (this.sceneLayer?.y ?? 0);
      this.tfnUpdateOutgoingEntry(entry, time);
      entry.holder.alpha = alpha * (1 - mix);
    }
  }
}
var LumierePixiRuntime = class _LumierePixiRuntime extends TfnPixiSceneHandoff {
  constructor(pixi, options, app) {
    super();
    this.pixi = pixi;
    this.options = options;
    this.app = app;
    this.sceneTuning = toLumiereSceneTuning(options.tuning, { showText: options.showText });
    this.audio = createLumiereAudioSampler({ audioPower: options.audioPower, audioBands: options.audioBands });
  }
  tfnUpdateOutgoingEntry(entry, time) {
    entry.unit.update(time);
  }
  tfnTop = 0;
  tfnBottom = 0;
  setTfnFrameRate(value) {
    this.app.ticker.maxFPS = Math.max(15, Math.min(60, value));
  }
  setTfnLyricScale(scale) {
    if (window.tfnLyricScale === scale) return;
    window.tfnLyricScale = scale;
    this.rebuildDue = true;
    this.renderOnce();
  }
  get tfnHeight() {
    return Math.max(120, this.height - this.tfnTop - this.tfnBottom);
  }
  setTfnInsets(top, bottom) {
    if (this.tfnTop === top && this.tfnBottom === bottom) return;
    this.tfnTop = top;
    this.tfnBottom = bottom;
    this.sceneLayer.y = top;
    this.credits.holder.y = top;
    this.rebuildDue = true;
    this.credits.invalidate();
    this.renderOnce();
  }
  setTfnActive(active) {
    if (!active) this.app.stop();
  }
  tfnLyricArrivalAt = null;
  startTfnLyricArrival() {
    if (!this.options.paused && !this.options.staticMode) this.tfnLyricArrivalAt = performance.now();
  }
  tfnLyricArrivalElapsed = () => this.tfnLyricArrivalAt === null || this.options.staticMode || this.options.paused ? Infinity : Math.max(0, (performance.now() - this.tfnLyricArrivalAt) / 1e3);
  /** 换歌时换下来的场景进缓存的 retired 队列，之后一帧销毁一个，免得交接那一帧卡住。 */
  sceneCache = new PixiSceneCache({
    count: () => this.options.song.program.paragraphs.length,
    build: (index) => {
      const entry = this.buildEntry(this.options.song, index);
      this.sceneLayer.addChild(entry.holder);
      return entry;
    },
    destroy: (entry) => this.destroyEntry(entry),
    detach: (entry) => entry.holder.parent?.removeChild(entry.holder)
  });
  activeIndex = -1;
  destroyed = false;
  resizeObserver = null;
  width = 0;
  height = 0;
  renderResolution = 1;
  quality = {
    bloom: 1,
    textBloom: 1,
    graphicsResolution: null,
    bloomLevelDrop: 0,
    passthrough: null
  };
  /** 所有场景共用、就地修改的场景 tuning：每帧现读的字段改了立刻生效（见 LUMIERE_LIVE_SCENE_KEYS）。 */
  sceneTuning;
  rebuildTimer = null;
  rebuildDue = false;
  songSwap = new PixiSongSwap({
    stage: (song) => this.stageSong(song),
    commit: (song, staged) => this.commitSong(song, staged),
    discard: (entry) => this.destroyEntry(entry)
  });
  audio;
  audioAt = () => this.audio.frame;
  /** 暗场底：在所有场景与片尾卡之下，不随段落转场变（见 lumiereDarkField.ts）。 */
  darkField;
  sceneLayer;
  overlayLayer;
  credits;
  sprites;
  passthrough;
  static async create(options) {
    const pixi = await loadPixi();
    const contextOptions = {
      // 画布透明：folia 的共享背景层要透出来，由运行时的暗场层按暗场强度压暗。
      backgroundAlpha: 0,
      // 大头（图形组）画进 filter 纹理，MSAA 管不到；只剩画框细线，不值得整屏多重采样的解析开销。
      // 所以默认关；用户在「抗锯齿」里选了开才开。
      antialias: options.antialias,
      powerPreference: "high-performance"
    };
    const context = await makePixiContext(pixi, contextOptions, options.signal);
    const app = new pixi.Application();
    const width = Math.max(options.host.clientWidth, MIN_WIDTH);
    const height = Math.max(options.host.clientHeight, MIN_HEIGHT);
    const resolution = resolveLumiereScaledRenderResolution(Math.min(window.devicePixelRatio || 1, window.tfnPerformance?.pixelRatioCap ?? 1.5), options.renderScale);
    await app.init({
      width,
      height,
      ...contextOptions,
      ...context,
      autoDensity: true,
      resolution,
      autoStart: false,
      sharedTicker: false,
      preference: "webgl"
    });
    if (app.renderer.type !== pixi.RendererType.WEBGL) {
      app.destroy({ removeView: true });
      throw new Error("Lumiere requires WebGL");
    }
    const runtime = new _LumierePixiRuntime(pixi, options, app);
    runtime.renderResolution = resolution;
    runtime.sprites = createLightSprites(pixi);
    runtime.passthrough = new pixi.AlphaFilter({ alpha: 1 });
    runtime.quality.passthrough = runtime.passthrough;
    runtime.darkField = new LumiereDarkFieldLayer(pixi);
    runtime.sceneLayer = new pixi.Container();
    runtime.sceneLayer.sortableChildren = true;
    runtime.overlayLayer = new pixi.Container();
    runtime.credits = new LumiereCreditsLayer(pixi, runtime.sprites);
    app.stage.addChild(runtime.darkField.view, runtime.sceneLayer, runtime.credits.holder, runtime.overlayLayer);
    if (options.signal?.aborted) {
      runtime.destroy();
      throw new DOMException("Lumiere runtime creation was cancelled", "AbortError");
    }
    await runtime.install();
    if (options.signal?.aborted) {
      runtime.destroy();
      throw new DOMException("Lumiere runtime creation was cancelled", "AbortError");
    }
    return runtime;
  }
  /**
   * 第一帧分几步做，步与步之间页面照常跑：建 WebGL 上下文之后另起一个任务建第一个场景，它的着色器程序
   * 在页面照常跑时链接（linkPixiPrograms），之后画布才放上页面、画出来。中途取消就提前返回。
   */
  async install() {
    await new Promise((resolve) => {
      window.setTimeout(resolve);
    });
    if (this.options.signal?.aborted) return;
    this.resizeToHost(true);
    this.renderFrame();
    await linkPixiPrograms(this.pixi, this.app.renderer, this.app.stage, "Lumiere", this.options.signal);
    if (this.options.signal?.aborted) return;
    this.options.host.appendChild(this.app.canvas);
    this.app.canvas.style.cssText = "width:100%;height:100%;display:block";
    this.app.ticker.maxFPS = window.tfnPerformance?.maxFps ?? 30;
    this.app.ticker.add(this.renderFrame);
    this.resizeObserver = new ResizeObserver(() => {
      if (this.destroyed || !this.resizeToHost(false)) return;
      if (this.options.paused) this.renderOnce();
    });
    this.resizeObserver.observe(this.options.host);
    this.app.renderer.render(this.app.stage);
    if (!this.options.paused) this.app.start();
  }
  /** 尺寸没变返回 false。渲染器立刻跟上，场景（尺寸烘焙在里面）防抖重建。 */
  resizeToHost(immediate) {
    if (this.destroyed) return false;
    const width = Math.max(this.options.host.clientWidth, MIN_WIDTH);
    const height = Math.max(this.options.host.clientHeight, MIN_HEIGHT);
    const resolution = resolveLumiereScaledRenderResolution(Math.min(window.devicePixelRatio || 1, window.tfnPerformance?.pixelRatioCap ?? 1.5), this.options.renderScale);
    if (width === this.width && height === this.height && resolution === this.renderResolution) return false;
    this.width = width;
    this.height = height;
    this.renderResolution = resolution;
    this.app.renderer.resize(width, height, resolution);
    this.refreshQuality();
    this.drawOverlay();
    if (immediate) this.rebuildDue = true;
    else this.scheduleRebuild();
    return true;
  }
  /** 画质档 + 视口 → 图形组分辨率与 bloom 减级，写到所有现存场景与片尾卡上。 */
  refreshQuality() {
    const graphicsResolution = resolveLumiereGraphicsResolution(
      this.width,
      this.height,
      this.renderResolution,
      this.options.tuning.renderQuality
    );
    this.quality.bloom = this.sceneTuning.bloom;
    this.quality.textBloom = this.sceneTuning.textBloom;
    this.quality.graphicsResolution = graphicsResolution < this.renderResolution ? graphicsResolution : null;
    this.quality.bloomLevelDrop = resolveLumiereBloomLevelDrop(this.renderResolution, graphicsResolution);
    this.sceneCache.forEach((entry) => applyLumiereSceneQuality(entry.unit.scene, this.quality));
    if (this.songSwap.staged) applyLumiereSceneQuality(this.songSwap.staged.unit.scene, this.quality);
    this.credits.applyQuality(this.quality);
  }
  scheduleRebuild() {
    if (this.rebuildTimer !== null) clearTimeout(this.rebuildTimer);
    this.rebuildTimer = setTimeout(() => {
      this.rebuildTimer = null;
      if (this.destroyed) return;
      this.rebuildDue = true;
      if (this.options.paused) this.renderOnce();
    }, REBUILD_DEBOUNCE_MS);
  }
  drawOverlay() {
    this.overlayLayer.removeChildren().forEach((child) => child.destroy({ children: true, context: true }));
    if (!this.options.tuning.overlayFrame || this.options.tuning.textOnly || this.width === 0) return;
    this.overlayLayer.addChild(buildLumiereOverlay(this.pixi, {
      width: this.width,
      height: this.height,
      theme: this.options.song.theme,
      themeColorMix: this.options.tuning.themeColorMix
    }));
  }
  buildEntry(song, index) {
    const entry = buildLumiereSceneEntry(this.pixi, {
      width: this.width,
      height: this.tfnHeight,
      resolution: this.renderResolution,
      program: song.program,
      theme: song.theme,
      tuning: this.sceneTuning,
      sprites: this.sprites,
      audioAt: this.audioAt,
      tfnArrivalElapsed: this.tfnLyricArrivalElapsed,
      showText: this.options.showText,
      quality: this.quality
    }, index);
    for (const layer of [entry.unit.scene.graphics, entry.unit.scene.front]) {
      layer.y = -this.tfnTop;
      layer.scale.y = this.height / this.tfnHeight;
    }
    return entry;
  }
  destroyEntry(entry) {
    destroyLumiereSceneEntry(entry, this.passthrough);
  }
  clearScenes() {
    this.tfnRetainScenes();
    this.sceneCache.clear();
    this.activeIndex = -1;
  }
  renderFrame = () => {
    if (this.destroyed) return;
    this.audio.sample(performance.now(), this.options.paused);
    this.songSwap.advance();
    const playbackTime = this.options.currentTime.get();
    const time = this.songSwap.active ? this.tfnLastSceneTime ?? playbackTime : playbackTime;
    if (this.rebuildDue && !this.tfnSceneHandoff) {
      this.rebuildDue = false;
      this.songSwap.dropStaged();
      this.clearScenes();
      this.credits.invalidate();
    }
    const { program, theme } = this.options.song;
    const frames = resolveLumiereSceneFrames(program, time, !this.options.staticMode);
    let builtThisFrame = false;
    if (frames.activeIndex !== this.activeIndex) {
      this.activeIndex = frames.activeIndex;
      this.sceneCache.prune(frames.activeIndex, new Set(frames.layers.map((layer) => layer.index)));
    }
    frames.layers.forEach((layer) => {
      if (!this.sceneCache.has(layer.index)) {
        this.sceneCache.ensure(layer.index);
        builtThisFrame = true;
      }
    });
    const creditsFrame = this.credits.resolveFrame(time, program, this.options.metadata);
    if (!builtThisFrame && !this.songSwap.active && !this.tfnSceneHandoff) {
      const next = frames.activeIndex + 1;
      const previous = frames.activeIndex - 1;
      if (this.sceneCache.hasRetired) {
        this.sceneCache.drainRetired();
      } else if (next < program.paragraphs.length && !this.sceneCache.has(next)) {
        this.sceneCache.ensure(next);
      } else if (this.credits.needsBuild(time, program, this.options.metadata)) {
        this.credits.build(this.creditBuildContext(theme));
      } else if (previous >= 0 && !this.sceneCache.has(previous)) {
        this.sceneCache.ensure(previous);
      }
    }
    if (creditsFrame.active && !this.credits.built && this.credits.hasMetadata(this.options.metadata)) {
      this.credits.build(this.creditBuildContext(theme));
    }
    const sceneMix = this.tfnSceneMix();
    const outgoingTheme = this.tfnSceneHandoff?.theme;
    const fieldTheme = outgoingTheme ? { ...theme, backgroundColor: "#" + hexOf(mixRgb(rgbOf(outgoingTheme.backgroundColor), rgbOf(theme.backgroundColor), sceneMix)).toString(16).padStart(6, "0") } : theme;
    this.darkField.update(fieldTheme, this.sceneTuning.darkField, this.width, this.height);
    this.options.host.ownerDocument.documentElement.style.setProperty("--accent", fieldTheme.backgroundColor);
    const lyricAlpha = creditsFrame.active ? creditsFrame.lyricAlpha : 1;
    const lyricBlur = creditsFrame.active ? creditsFrame.lyricBlur : 0;
    const blurResolution = this.renderResolution * 0.5;
    this.sceneCache.forEach((entry, index) => {
      const layer = frames.layers.find((candidate) => candidate.index === index);
      const alpha = (layer?.alpha ?? 0) * lyricAlpha * sceneMix;
      entry.holder.visible = alpha > 2e-3;
      if (!entry.holder.visible || !layer) return;
      entry.unit.update(time);
      applyLumiereLayerFrame(this.pixi, entry, {
        alpha,
        scale: layer.scale,
        blur: Math.max(layer.blur, lyricBlur)
      }, blurResolution);
    });
    this.tfnRenderOutgoing(sceneMix);
    this.tfnLastSceneTime = time;
    this.tfnLastSceneTop = this.sceneLayer.y;
    this.credits.update(time, creditsFrame, this.width, this.tfnHeight);
    if (this.credits.holder.visible) this.credits.holder.y += this.tfnTop;
  };
  creditBuildContext(theme) {
    return {
      width: this.width,
      height: this.tfnHeight,
      resolution: this.renderResolution,
      theme,
      metadata: this.options.metadata,
      tuning: this.sceneTuning,
      quality: this.quality
    };
  }
  renderOnce() {
    if (this.destroyed || !this.app.canvas.isConnected) return;
    this.renderFrame();
    if (this.destroyed) return;
    this.app.renderer.render(this.app.stage);
  }
  /**
   * 换歌：新歌当前段落的场景在第一帧建好（旧歌还在画），第二帧切过去；换下的场景之后一帧销毁一个。
   * 不是真正的换歌（同一个 seed：主题改了、歌词晚到）、暂停中、还没有画面时直接替换。
   */
  async swapSong(next, signal) {
    await this.tfnSceneHandoff?.finished;
    if (this.destroyed || signal?.aborted) return;
    if (sameTfnTrack(next, this.options.song) || this.songSwap.active || this.width === 0 || this.sceneCache.size === 0 || this.options.paused) {
      this.commitSong(next, null);
      if (this.options.paused) this.renderOnce();
    } else {
      await this.songSwap.begin(next, signal);
    }
    await this.tfnSceneHandoff?.finished;
  }
  /** 交接的第一帧：离屏建好新歌当前段落的场景（不进缓存，旧歌的场景被换下时它不受影响）。 */
  stageSong(song) {
    const index = findLumiereParagraphIndexAtTime(song.program, song.currentTime?.get() ?? this.options.currentTime.get());
    if (index < 0 || index >= song.program.paragraphs.length) return null;
    const entry = this.buildEntry(song, index);
    entry.holder.visible = false;
    this.sceneLayer.addChild(entry.holder);
    return entry;
  }
  commitSong(next, staged) {
    const trackChanged = !sameTfnTrack(next, this.options.song);
    const arrivingDuringMix = trackChanged && next.mixHandoff && !next.program.instrumental;
    const lyricsArrived = !trackChanged && this.options.song.program.instrumental && !next.program.instrumental;
    if (!this.options.paused && !this.options.staticMode && (arrivingDuringMix || lyricsArrived)) {
      this.startTfnLyricArrival();
    } else if (trackChanged) {
      this.tfnLyricArrivalAt = null;
    }
    this.tfnRetainScenes();
    const themeChanged = next.theme !== this.options.song.theme;
    this.options.song = next;
    if (staged) {
      this.sceneCache.retireAll();
      this.sceneCache.adopt(staged.index, staged);
      this.activeIndex = staged.index;
    } else {
      this.clearScenes();
    }
    this.credits.invalidate();
    if (themeChanged) this.drawOverlay();
  }
  /** 就地应用 tuning：每帧现读的字段直接改，bloom 强度写进 filter，烘焙进场景的字段防抖重建。 */
  setTuning(tuning) {
    if (this.destroyed || tuning === this.options.tuning) return;
    const previousTuning = this.options.tuning;
    this.options.tuning = tuning;
    this.applySceneTuning();
    if (previousTuning.overlayFrame !== tuning.overlayFrame || previousTuning.textOnly !== tuning.textOnly || previousTuning.themeColorMix !== tuning.themeColorMix) this.drawOverlay();
    if (this.options.paused) this.renderOnce();
  }
  /** 就地换分辨率倍数：同窗口缩放，渲染器立刻跟上，图形组画质随之重算，场景（字按分辨率光栅化）防抖重建。 */
  setRenderScale(scale) {
    if (this.destroyed || scale === this.options.renderScale) return;
    this.options.renderScale = scale;
    if (this.width === 0) return;
    if (this.resizeToHost(false) && this.options.paused) this.renderOnce();
  }
  setShowText(showText) {
    if (this.destroyed || showText === this.options.showText) return;
    this.options.showText = showText;
    this.sceneCache.forEach((entry) => {
      entry.unit.scene.text.visible = showText;
    });
    if (this.songSwap.staged) this.songSwap.staged.unit.scene.text.visible = showText;
    this.applySceneTuning();
    if (this.options.paused) this.renderOnce();
  }
  applySceneTuning() {
    const previous = { ...this.sceneTuning };
    const next = toLumiereSceneTuning(this.options.tuning, { showText: this.options.showText });
    Object.assign(this.sceneTuning, next);
    this.refreshQuality();
    if (requiresLumiereSceneRebuild(previous, next)) this.scheduleRebuild();
  }
  setStaticMode(staticMode) {
    if (this.destroyed || staticMode === this.options.staticMode) return;
    if (staticMode) this.tfnLyricArrivalAt = null;
    if (staticMode) this.tfnFinishSceneHandoff();
    this.options.staticMode = staticMode;
    if (this.options.paused) this.renderOnce();
  }
  setAudioSources(audioPower, audioBands) {
    this.audio.setSources({ audioPower, audioBands });
  }
  setSongMetadata(metadata) {
    if (this.destroyed) return;
    const current = this.options.metadata;
    if (current.title === metadata.title && current.artist === metadata.artist && current.album === metadata.album) return;
    this.options.metadata = { ...metadata };
    this.credits.invalidate();
    if (this.options.paused) this.renderOnce();
  }
  setPaused(paused) {
    if (this.destroyed) return;
    if (paused) this.tfnLyricArrivalAt = null;
    if (paused) this.tfnFinishSceneHandoff();
    this.options.paused = paused;
    if (paused) {
      this.songSwap.settle(true);
      this.app.stop();
      this.renderOnce();
    } else {
      this.app.start();
    }
  }
  destroy() {
    if (this.destroyed) return;
    this.destroyed = true;
    this.songSwap.settle(false);
    if (this.rebuildTimer !== null) clearTimeout(this.rebuildTimer);
    this.rebuildTimer = null;
    this.resizeObserver?.disconnect();
    this.resizeObserver = null;
    this.app.stop();
    this.app.ticker.remove(this.renderFrame);
    this.tfnFinishSceneHandoff();
    this.sceneCache.destroyAll();
    this.credits?.destroy();
    this.darkField?.destroy();
    this.overlayLayer?.removeChildren().forEach((child) => child.destroy({ children: true, context: true }));
    this.sprites?.destroy();
    this.passthrough?.destroy();
    this.app.destroy({ removeView: true }, { children: true });
  }
};

// folia:src/types.ts
var DEFAULT_LUMIERE_TUNING = {
  render: { scale: "global", antialias: "global" },
  lightIntensity: 1,
  audioResponse: 1,
  fogDensity: 1,
  darkField: 0.75,
  moteAmount: 1,
  bloom: 1,
  textBloom: 1,
  unlitOpacity: 0.22,
  windowNeighbors: 2,
  decay: 1,
  echo: 1,
  fogOctaves: 5,
  lineArt: true,
  frontBokeh: true,
  trails: true,
  hideTrails: false,
  seamlessTransitions: true,
  overlayFrame: true,
  textOnly: false,
  keywordColors: true,
  themeIcons: true,
  themeColorMix: 0.3,
  renderQuality: "full"
};

// folia:src/components/visualizer/tfnLyricViewport.ts
var TfnLyricViewport = class {
  from = null;
  target = null;
  at = 0;
  duration = 0;
  set(top, bottom, animate = true, now = performance.now()) {
    if (this.target?.top === top && this.target?.bottom === bottom) {
      if (!animate) this.finish();
      return;
    }
    const current = this.sample(now);
    this.from = current ?? { top, bottom };
    this.target = { top, bottom };
    this.at = now;
    this.duration = current && animate ? bottom > current.bottom ? 600 : 560 : 0;
  }
  finish() {
    this.duration = 0;
  }
  get moving() {
    return this.duration > 0;
  }
  sample(now = performance.now()) {
    if (!this.target) return null;
    const t = this.duration ? Math.min(1, Math.max(0, (now - this.at) / this.duration)) : 1;
    if (t === 1) {
      this.finish();
      return this.target;
    }
    let lo = 0, hi = 1;
    const cubic = (u, a, b) => 3 * (1 - u) * (1 - u) * u * a + 3 * (1 - u) * u * u * b + u * u * u;
    for (let i = 0; i < 18; i++) {
      const u = (lo + hi) / 2;
      if (cubic(u, 0.645, 0.355) < t) lo = u;
      else hi = u;
    }
    const mix = t === 0 ? 0 : cubic((lo + hi) / 2, 0.045, 1);
    return {
      top: this.from.top + (this.target.top - this.from.top) * mix,
      bottom: this.from.bottom + (this.target.bottom - this.from.bottom) * mix
    };
  }
};
function tfnProjectLyric(y, height, base, current) {
  const before = Math.max(120, height - base.top - base.bottom);
  const after = Math.max(120, height - current.top - current.bottom);
  return {
    y: current.top + (y - base.top) * after / before,
    scale: Math.min(1, after / before)
  };
}

// folia:src/services/beatFx/beatEffects.ts
var BEAT_EFFECT_IDS = {};

// folia:src/services/beatFx/beatFxLive.ts
var getBeatEffectStrength = () => 0;
var getBeatFxEvents = () => [];
var isBeatFxReady = () => false;
var getBeatFxTrackScale = () => 1;
var getBeatFxIntensities = () => ({});
var getBeatFxRotationSign = () => 1;

// folia:src/stores/motionSignals.ts
var beatImpact = { get: () => 0 };
var downbeatImpact = { get: () => 0 };

// folia:src/components/visualizer/pixi/pixiDisplayResources.ts
var destroyPixiDisplayTree = (root) => {
  const order = [];
  const stack = [root];
  while (stack.length > 0) {
    const node2 = stack.pop();
    order.push(node2);
    if (node2.children?.length) stack.push(...node2.children);
  }
  for (let index = order.length - 1; index >= 0; index -= 1) order[index].destroy?.();
};
var destroyPixiContainerChildren = (container) => {
  container.removeChildren().forEach(destroyPixiDisplayTree);
};

// folia:src/components/visualizer/hanabi/catalog.ts
var BURST_PRESETS = {
  kiku: { count: 96, radius: 0.3, duration: 1.9, trail: 0.65, twinkle: 0.2 },
  botan: { count: 84, radius: 0.26, duration: 1.4, trail: 0.1, twinkle: 0.1 },
  yanagi: { count: 64, radius: 0.3, duration: 3.2, trail: 0.9, twinkle: 0.3 },
  kamuro: { count: 110, radius: 0.36, duration: 3.6, trail: 0.95, twinkle: 0.55 },
  senrin: { count: 72, radius: 0.22, duration: 1.7, trail: 0.3, twinkle: 0.45 },
  ring: { count: 60, radius: 0.26, duration: 1.4, trail: 0.3, twinkle: 0.1 },
  heart: { count: 60, radius: 0.2, duration: 1.6, trail: 0.2, twinkle: 0.2 },
  star: { count: 55, radius: 0.2, duration: 1.6, trail: 0.2, twinkle: 0.3 },
  palm: { count: 36, radius: 0.32, duration: 2.3, trail: 0.8, twinkle: 0.1 },
  crossette: { count: 40, radius: 0.26, duration: 1.9, trail: 0.4, twinkle: 0.2 },
  strobe: { count: 72, radius: 0.28, duration: 2.3, trail: 0.15, twinkle: 1 },
  hachi: { count: 50, radius: 0.24, duration: 1.6, trail: 0.6, twinkle: 0.5 },
  "willow-ring": { count: 100, radius: 0.34, duration: 2.8, trail: 0.7, twinkle: 0.3 },
  mine: { count: 84, radius: 0.5, duration: 1.8, trail: 0.7, twinkle: 0.3 }
};
var BURST_KINDS = Object.keys(BURST_PRESETS);
var burstPreset = (kind, colors = [0, 1, 2]) => ({ kind, colors, ...BURST_PRESETS[kind] });
var burst = (kind, colors, patch = {}) => ({ ...burstPreset(kind, colors), ...patch });
var small = (kind, colors, patch = {}) => ({
  ...burstPreset(kind, colors),
  count: 14,
  radius: 0.05,
  duration: 0.8,
  ...patch
});
var orn = (kind, placement, layer, patch = {}) => ({ kind, placement, layer, density: 0.6, scale: 1, color: "accent", delay: 0, ...patch });
var REGIONS = {
  center: { cx: 0.5, cy: 0.5, w: 0.74, h: 0.34 },
  centerHigh: { cx: 0.5, cy: 0.45, w: 0.72, h: 0.32 },
  left: { cx: 0.42, cy: 0.56, w: 0.6, h: 0.34 },
  right: { cx: 0.58, cy: 0.46, w: 0.6, h: 0.34 },
  stagger: { cx: 0.5, cy: 0.5, w: 0.7, h: 0.46 },
  diagonal: { cx: 0.5, cy: 0.5, w: 0.74, h: 0.5 },
  scatter: { cx: 0.5, cy: 0.5, w: 0.78, h: 0.56 },
  vertical: { cx: 0.5, cy: 0.5, w: 0.34, h: 0.72 },
  verticalRight: { cx: 0.62, cy: 0.5, w: 0.3, h: 0.72 },
  verticalSplit: { cx: 0.5, cy: 0.5, w: 0.46, h: 0.72 },
  arc: { cx: 0.5, cy: 0.54, w: 0.74, h: 0.4 },
  giant: { cx: 0.5, cy: 0.5, w: 0.8, h: 0.52 },
  giantLeft: { cx: 0.44, cy: 0.52, w: 0.68, h: 0.5 }
};
var REGION_OF_LAYOUT = {
  center: REGIONS.center,
  left: REGIONS.left,
  right: REGIONS.right,
  stagger: REGIONS.stagger,
  diagonal: REGIONS.diagonal,
  scatter: REGIONS.scatter,
  vertical: REGIONS.vertical,
  "vertical-split": REGIONS.verticalSplit,
  arc: REGIONS.arc
};
var family = (id, base, recipes) => recipes.map((recipe) => ({
  kind: recipe.kind,
  label: recipe.label,
  family: id,
  mood: recipe.mood,
  text: {
    ...base.text,
    ...recipe.text,
    layout: recipe.layout,
    block: recipe.block,
    enter: recipe.enter,
    sing: recipe.sing,
    exit: recipe.exit
  },
  region: recipe.region ?? REGION_OF_LAYOUT[recipe.layout],
  burst: recipe.burst,
  burstAt: recipe.burstAt ?? base.burstAt,
  sungBurst: recipe.sungBurst !== void 0 ? recipe.sungBurst : base.sungBurst,
  ornaments: recipe.ornaments,
  launch: recipe.launch ?? base.launch,
  palette: recipe.palette,
  camera: { ...base.camera, ...recipe.camera }
}));
var UCHIAGE = family("uchiage", {
  text: { heroSize: 0.1, emphasis: 0.45, tilt: 0, stagger: 0.045, outline: false, hardShadow: true },
  burstAt: "above",
  sungBurst: null,
  launch: true,
  camera: { rise: 0.72, push: 0.04, roll: 0.01, punch: 0.35 }
}, [
  {
    kind: "uchiage-kiku",
    label: "\u6253\u4E0A\xB7\u83CA",
    mood: "neutral",
    layout: "center",
    block: "band",
    enter: "rise",
    sing: "bounce",
    exit: "ascend",
    palette: "kawaii",
    burst: burst("kiku", [0, 1, 2]),
    ornaments: [
      orn("streaks", "screen", "back", { density: 0.5, color: "spark", delay: -0.3 }),
      orn("sparkle", "glyphs", "front", { density: 0.5, color: "glow" }),
      orn("ring", "behind", "back", { scale: 1.1, color: "spark", delay: 0.05 })
    ]
  },
  {
    kind: "uchiage-botan",
    label: "\u6253\u4E0A\xB7\u7261\u4E39",
    mood: "loud",
    layout: "stagger",
    block: "pill",
    enter: "rise",
    sing: "jump",
    exit: "ascend",
    palette: "festival",
    burst: burst("botan", [0, 1, 2, 3], { count: 96 }),
    sungBurst: small("botan", [0, 1, 2]),
    ornaments: [
      orn("chevrons", "line-end", "back", { density: 0.7, color: "block" }),
      orn("confetti", "screen", "front", { density: 0.55, color: "spark", delay: 0.1 }),
      orn("dots-line", "glyphs", "back", { density: 0.6, color: "paper" })
    ],
    camera: { rise: 0.8, punch: 0.5 }
  },
  {
    kind: "uchiage-palm",
    label: "\u6253\u4E0A\xB7\u6930",
    mood: "neutral",
    layout: "left",
    block: "slant",
    enter: "elastic",
    sing: "swell",
    exit: "ascend",
    palette: "ocean",
    burst: burst("palm", [0, 1]),
    burstAt: "sides",
    text: { tilt: -0.05 },
    ornaments: [
      orn("streaks", "line-start", "back", { density: 0.45, color: "spark" }),
      orn("underline", "glyphs", "back", { color: "block", scale: 1.1 }),
      orn("cross", "around", "front", { density: 0.4, scale: 0.8, color: "paper" })
    ]
  },
  {
    kind: "uchiage-crossette",
    label: "\u6253\u4E0A\xB7\u5206\u88C2",
    mood: "neutral",
    layout: "arc",
    block: "none",
    enter: "wave",
    sing: "flash",
    exit: "ascend",
    palette: "night",
    burst: burst("crossette", [0, 2, 3]),
    text: { outline: true, hardShadow: false, heroSize: 0.095 },
    ornaments: [
      orn("dash-circle", "behind", "back", { scale: 1.2, color: "glow", delay: -0.1 }),
      orn("sparkle", "glyphs", "front", { density: 0.7, color: "spark" }),
      orn("streaks", "screen", "back", { density: 0.35, color: "paper", delay: -0.4 })
    ]
  },
  {
    kind: "uchiage-double",
    label: "\u6253\u4E0A\xB7\u9526",
    mood: "neutral",
    layout: "center",
    block: "double",
    enter: "drop",
    sing: "bounce",
    exit: "scatter",
    palette: "gold",
    burst: burst("willow-ring", [0, 1, 2]),
    burstAt: "behind",
    ornaments: [
      orn("rays", "behind", "back", { density: 0.5, scale: 1.2, color: "glow", delay: 0.05 }),
      orn("glints", "glyphs", "front", { density: 0.6, color: "paper" }),
      orn("chevrons", "line-start", "back", { density: 0.5, color: "accent" })
    ],
    camera: { rise: 0.65 }
  }
]);
var KIKU = family("kiku", {
  text: { heroSize: 0.13, emphasis: 0.35, tilt: 0, stagger: 0.035, outline: true, hardShadow: false },
  burstAt: "behind",
  sungBurst: null,
  launch: true,
  camera: { rise: 0.55, push: 0.07, roll: 0, punch: 0.5 }
}, [
  {
    kind: "kiku-center",
    label: "\u83CA\xB7\u6B63\u9762",
    mood: "loud",
    layout: "center",
    block: "none",
    enter: "zoom",
    sing: "glow",
    exit: "shrink",
    palette: "night",
    burst: burst("kiku", [0, 1, 2, 3], { count: 120, radius: 0.36 }),
    ornaments: [
      orn("spokes", "behind", "back", { density: 0.8, scale: 1.3, color: "paper", delay: 0.05 }),
      orn("ring", "behind", "back", { density: 0.7, scale: 1.4, color: "spark", delay: 0.1 }),
      orn("glints", "glyphs", "front", { density: 0.5, color: "glow" })
    ]
  },
  {
    kind: "kiku-ring",
    label: "\u83CA\xB7\u8F2A",
    mood: "loud",
    layout: "center",
    block: "outline",
    enter: "burst",
    sing: "flash",
    exit: "dissolve",
    palette: "neon",
    burst: burst("ring", [0, 1, 2], { count: 72 }),
    ornaments: [
      orn("ring", "around", "back", { density: 0.9, scale: 1.2, color: "accent" }),
      orn("dash-circle", "behind", "back", { scale: 1.5, color: "glow", delay: -0.15 }),
      orn("sparkle", "glyphs", "front", { density: 0.6, color: "spark" })
    ],
    camera: { punch: 0.65 }
  },
  {
    kind: "kiku-spokes",
    label: "\u83CA\xB7\u96C6\u4E2D\u7EBF",
    mood: "neutral",
    layout: "center",
    block: "circle",
    enter: "pop",
    sing: "bounce",
    exit: "scatter",
    palette: "festival",
    burst: burst("kiku", [1, 2, 0]),
    text: { heroSize: 0.11, outline: false, hardShadow: true },
    ornaments: [
      orn("spokes", "around", "back", { density: 0.9, scale: 1.1, color: "block" }),
      orn("shards", "around", "front", { density: 0.45, color: "spark", delay: 0.1 }),
      orn("ring", "behind", "back", { density: 0.5, color: "paper", delay: 0.15 })
    ]
  },
  {
    kind: "kiku-halo",
    label: "\u83CA\xB7\u5149\u51A0",
    mood: "neutral",
    layout: "arc",
    block: "tile",
    enter: "spiral",
    sing: "swell",
    exit: "ascend",
    palette: "gold",
    burst: burst("kamuro", [0, 1], { radius: 0.32 }),
    burstAt: "above",
    text: { heroSize: 0.1, outline: false },
    ornaments: [
      orn("dash-circle", "behind", "back", { scale: 1.3, color: "accent" }),
      orn("orbit", "around", "front", { density: 0.6, color: "glow" }),
      orn("glints", "glyphs", "front", { density: 0.4, color: "paper" })
    ],
    camera: { push: 0.05, roll: 0.012 }
  },
  {
    kind: "kiku-marker",
    label: "\u83CA\xB7\u8367\u5149",
    mood: "neutral",
    layout: "right",
    block: "marker",
    enter: "wipe",
    sing: "underline",
    exit: "slide",
    palette: "ocean",
    burst: burst("kiku", [0, 2]),
    burstAt: "sky",
    text: { heroSize: 0.1, outline: false, stagger: 0.05 },
    ornaments: [
      orn("ring", "line-start", "back", { density: 0.5, color: "spark" }),
      orn("spokes", "corners", "back", { density: 0.5, scale: 0.8, color: "paper" }),
      orn("dots-line", "glyphs", "front", { density: 0.6, color: "accent" })
    ],
    camera: { push: 0.03, punch: 0.25 }
  }
]);
var BOTAN = family("botan", {
  text: { heroSize: 0.11, emphasis: 0.6, tilt: 0, stagger: 0.05, outline: false, hardShadow: true },
  burstAt: "behind",
  sungBurst: null,
  launch: false,
  camera: { rise: 0.5, push: 0.05, roll: 0, punch: 0.6 }
}, [
  {
    kind: "botan-band",
    label: "\u7261\u4E39\xB7\u8272\u5E26",
    mood: "loud",
    layout: "center",
    block: "band",
    enter: "stamp",
    sing: "jump",
    exit: "shrink",
    palette: "festival",
    burst: burst("botan", [0, 1, 2, 3], { count: 110 }),
    text: { heroSize: 0.12 },
    ornaments: [
      orn("halftone", "behind", "back", { density: 0.7, scale: 1.3, color: "block" }),
      orn("confetti", "screen", "front", { density: 0.6, color: "spark", delay: 0.05 }),
      orn("squares", "around", "back", { density: 0.5, color: "accent" })
    ],
    camera: { punch: 0.8 }
  },
  {
    kind: "botan-tile",
    label: "\u7261\u4E39\xB7\u65B9\u5757",
    mood: "neutral",
    layout: "stagger",
    block: "tile",
    enter: "pop",
    sing: "color",
    exit: "scatter",
    palette: "pastel",
    burst: burst("botan", [1, 2, 3]),
    sungBurst: small("botan", [0, 1, 2, 3], { count: 10 }),
    ornaments: [
      orn("squares", "corners", "back", { density: 0.6, color: "block" }),
      orn("confetti", "screen", "front", { density: 0.4, color: "spark" }),
      orn("cross", "around", "front", { density: 0.5, scale: 0.8, color: "accent" })
    ],
    camera: { punch: 0.4 }
  },
  {
    kind: "botan-double",
    label: "\u7261\u4E39\xB7\u5FC3",
    mood: "loud",
    layout: "left",
    block: "double",
    enter: "stamp",
    sing: "bounce",
    exit: "blink",
    palette: "sakura",
    burst: burst("heart", [0, 2]),
    burstAt: "sides",
    text: { tilt: -0.04 },
    ornaments: [
      orn("halftone", "behind", "back", { density: 0.6, color: "accent" }),
      orn("stamp", "line-end", "front", { scale: 1.1, color: "accent", delay: 0.3 }),
      orn("sparkle", "glyphs", "front", { density: 0.5, color: "paper" })
    ]
  },
  {
    kind: "botan-split",
    label: "\u7261\u4E39\xB7\u53CC\u8272",
    mood: "loud",
    layout: "diagonal",
    block: "split",
    enter: "flip",
    sing: "jump",
    exit: "slide",
    palette: "neon",
    burst: burst("botan", [0, 1]),
    burstAt: "above",
    text: { tilt: -0.12 },
    ornaments: [
      orn("shards", "around", "front", { density: 0.55, color: "spark" }),
      orn("chevrons", "line-end", "back", { density: 0.7, color: "block" }),
      orn("zigzag", "around", "back", { density: 0.6, color: "accent" })
    ],
    camera: { roll: 0.02 }
  },
  {
    kind: "botan-circle",
    label: "\u7261\u4E39\xB7\u4E38",
    mood: "neutral",
    layout: "scatter",
    block: "circle",
    enter: "pop",
    sing: "bounce",
    exit: "shrink",
    palette: "pastel",
    burst: burst("star", [0, 1, 3]),
    burstAt: "sky",
    text: { heroSize: 0.09, emphasis: 0.8 },
    ornaments: [
      orn("cross", "screen", "back", { density: 0.5, color: "paper" }),
      orn("confetti", "around", "front", { density: 0.5, color: "block" }),
      orn("orbit", "around", "back", { density: 0.5, color: "accent" })
    ],
    camera: { punch: 0.35 }
  }
]);
var YANAGI = family("yanagi", {
  text: { heroSize: 0.085, emphasis: 0.2, tilt: 0, stagger: 0.09, outline: false, hardShadow: false },
  burstAt: "above",
  sungBurst: null,
  launch: true,
  camera: { rise: 0.35, push: 0.025, roll: 6e-3, punch: 0 }
}, [
  {
    kind: "yanagi-shidare",
    label: "\u67F3\xB7\u679D\u5782",
    mood: "quiet",
    layout: "vertical",
    block: "none",
    enter: "drop",
    sing: "glow",
    exit: "fall",
    palette: "night",
    burst: burst("yanagi", [0, 1]),
    ornaments: [
      orn("petals", "screen", "front", { density: 0.3, color: "glow", delay: 0.4 }),
      orn("dots-line", "glyphs", "back", { density: 0.5, scale: 0.8, color: "spark" }),
      orn("glints", "glyphs", "front", { density: 0.35, color: "paper" })
    ]
  },
  {
    kind: "yanagi-kamuro",
    label: "\u67F3\xB7\u91D1\u51A0",
    mood: "quiet",
    layout: "vertical-split",
    block: "outline",
    enter: "wipe",
    sing: "glow",
    exit: "fall",
    palette: "gold",
    burst: burst("kamuro", [0, 1, 2], { duration: 4 }),
    ornaments: [
      orn("brackets", "around", "back", { scale: 1.05, color: "accent", delay: 0.1 }),
      orn("glints", "glyphs", "front", { density: 0.4, color: "glow" }),
      orn("wave", "behind", "back", { density: 0.35, color: "spark" })
    ]
  },
  {
    kind: "yanagi-ame",
    label: "\u67F3\xB7\u96E8",
    mood: "quiet",
    layout: "vertical",
    block: "marker",
    enter: "wave",
    sing: "underline",
    exit: "fall",
    palette: "ocean",
    burst: burst("willow-ring", [0, 2], { count: 80 }),
    region: REGIONS.verticalRight,
    ornaments: [
      orn("wave", "screen", "back", { density: 0.4, color: "accent" }),
      orn("streaks", "screen", "back", { density: 0.3, scale: 0.8, color: "paper" }),
      orn("dots-line", "line-end", "front", { density: 0.5, color: "spark" })
    ]
  },
  {
    kind: "yanagi-kaze",
    label: "\u67F3\xB7\u98CE",
    mood: "quiet",
    layout: "right",
    block: "none",
    enter: "drop",
    sing: "swell",
    exit: "fall",
    palette: "sakura",
    burst: burst("yanagi", [0, 1, 3]),
    burstAt: "sky",
    text: { heroSize: 0.08, stagger: 0.07 },
    ornaments: [
      orn("petals", "screen", "front", { density: 0.5, color: "block" }),
      orn("sparkle", "glyphs", "front", { density: 0.35, color: "glow" }),
      orn("wave", "line-start", "back", { density: 0.4, color: "accent" })
    ]
  },
  {
    kind: "yanagi-palm",
    label: "\u67F3\xB7\u6930\u5F71",
    mood: "quiet",
    layout: "vertical-split",
    block: "pill",
    enter: "rise",
    sing: "color",
    exit: "dissolve",
    palette: "kawaii",
    burst: burst("palm", [0, 2], { duration: 2.8 }),
    burstAt: "sides",
    ornaments: [
      orn("brackets", "around", "back", { color: "paper", delay: 0.1 }),
      orn("petals", "screen", "front", { density: 0.25, color: "spark" }),
      orn("dash-circle", "behind", "back", { scale: 1.3, color: "glow" })
    ]
  }
]);
var SENRIN = family("senrin", {
  text: { heroSize: 0.09, emphasis: 0.7, tilt: 0, stagger: 0.03, outline: false, hardShadow: true },
  burstAt: "behind",
  sungBurst: small("senrin", [0, 1, 2, 3], { count: 16, radius: 0.06 }),
  launch: false,
  camera: { rise: 0.45, push: 0.04, roll: 0.012, punch: 0.4 }
}, [
  {
    kind: "senrin-scatter",
    label: "\u5343\u8F2A\xB7\u6563",
    mood: "loud",
    layout: "scatter",
    block: "pill",
    enter: "pop",
    sing: "jump",
    exit: "scatter",
    palette: "festival",
    burst: burst("senrin", [0, 1, 2, 3]),
    ornaments: [
      orn("confetti", "screen", "front", { density: 0.6, color: "spark" }),
      orn("cross", "around", "back", { density: 0.6, color: "accent" }),
      orn("sparkle", "glyphs", "front", { density: 0.5, color: "paper" })
    ]
  },
  {
    kind: "senrin-stagger",
    label: "\u5343\u8F2A\xB7\u9636",
    mood: "neutral",
    layout: "stagger",
    block: "tile",
    enter: "burst",
    sing: "bounce",
    exit: "shrink",
    palette: "neon",
    burst: burst("senrin", [1, 2, 3]),
    ornaments: [
      orn("squares", "around", "back", { density: 0.5, color: "block" }),
      orn("shards", "around", "front", { density: 0.45, color: "spark" }),
      orn("sparkle", "glyphs", "front", { density: 0.4, color: "glow" })
    ]
  },
  {
    kind: "senrin-strobe",
    label: "\u5343\u8F2A\xB7\u70B9\u6EC5",
    mood: "neutral",
    layout: "scatter",
    block: "circle",
    enter: "spin",
    sing: "flash",
    exit: "blink",
    palette: "pastel",
    burst: burst("strobe", [0, 1, 2, 3]),
    burstAt: "sky",
    sungBurst: small("strobe", [0, 1, 2, 3], { twinkle: 1 }),
    ornaments: [
      orn("cross", "screen", "back", { density: 0.5, color: "paper" }),
      orn("orbit", "around", "front", { density: 0.5, color: "spark" }),
      orn("dots-line", "glyphs", "back", { density: 0.5, color: "accent" })
    ]
  },
  {
    kind: "senrin-hachi",
    label: "\u5343\u8F2A\xB7\u8702",
    mood: "loud",
    layout: "diagonal",
    block: "stair",
    enter: "spin",
    sing: "shake",
    exit: "scatter",
    palette: "festival",
    burst: burst("hachi", [0, 1, 2]),
    sungBurst: small("hachi", [0, 1, 2], { count: 12 }),
    text: { tilt: -0.1 },
    ornaments: [
      orn("zigzag", "around", "back", { density: 0.7, color: "block" }),
      orn("confetti", "screen", "front", { density: 0.5, color: "spark" }),
      orn("chevrons", "line-end", "front", { density: 0.5, color: "paper" })
    ],
    camera: { roll: 0.02, punch: 0.55 }
  },
  {
    kind: "senrin-heart",
    label: "\u5343\u8F2A\xB7\u5FC3",
    mood: "neutral",
    layout: "arc",
    block: "pill",
    enter: "pop",
    sing: "bounce",
    exit: "shrink",
    palette: "sakura",
    burst: burst("heart", [0, 1]),
    burstAt: "above",
    sungBurst: small("heart", [0, 2], { count: 12 }),
    ornaments: [
      orn("petals", "screen", "front", { density: 0.45, color: "block" }),
      orn("confetti", "around", "front", { density: 0.35, color: "spark" }),
      orn("sparkle", "glyphs", "front", { density: 0.4, color: "paper" })
    ]
  }
]);
var HOSHIKUZU = family("hoshikuzu", {
  text: { heroSize: 0.085, emphasis: 0.3, tilt: 0, stagger: 0.07, outline: false, hardShadow: false },
  burstAt: "sky",
  sungBurst: small("star", [0, 1, 2], { count: 10, radius: 0.04, duration: 1 }),
  launch: false,
  camera: { rise: 0.4, push: 0.03, roll: 8e-3, punch: 0 }
}, [
  {
    kind: "hoshikuzu-star",
    label: "\u661F\u5C51\xB7\u661F",
    mood: "quiet",
    layout: "center",
    block: "none",
    enter: "spiral",
    sing: "glow",
    exit: "dissolve",
    palette: "night",
    burst: burst("star", [0, 2]),
    burstAt: "above",
    ornaments: [
      orn("sparkle", "glyphs", "front", { density: 0.7, color: "glow" }),
      orn("glints", "glyphs", "front", { density: 0.5, color: "paper" }),
      orn("orbit", "around", "back", { density: 0.4, scale: 1.2, color: "spark" })
    ]
  },
  {
    kind: "hoshikuzu-orbit",
    label: "\u661F\u5C51\xB7\u8F68\u9053",
    mood: "quiet",
    layout: "arc",
    block: "outline",
    enter: "zoom",
    sing: "glow",
    exit: "dissolve",
    palette: "ocean",
    burst: burst("strobe", [0, 1, 2], { count: 56 }),
    ornaments: [
      orn("orbit", "around", "front", { density: 0.7, color: "glow" }),
      orn("dash-circle", "behind", "back", { scale: 1.4, color: "accent" }),
      orn("sparkle", "around", "front", { density: 0.4, color: "paper" })
    ]
  },
  {
    kind: "hoshikuzu-dust",
    label: "\u661F\u5C51\xB7\u5C18",
    mood: "quiet",
    layout: "vertical",
    block: "circle",
    enter: "wave",
    sing: "glow",
    exit: "dissolve",
    palette: "pastel",
    burst: burst("ring", [0, 1], { count: 48, radius: 0.2 }),
    burstAt: "behind",
    ornaments: [
      orn("dots-line", "glyphs", "back", { density: 0.6, color: "spark" }),
      orn("sparkle", "screen", "front", { density: 0.45, color: "glow" }),
      orn("petals", "screen", "front", { density: 0.2, scale: 0.7, color: "paper" })
    ]
  },
  {
    kind: "hoshikuzu-line",
    label: "\u661F\u5C51\xB7\u70B9\u7EBF",
    mood: "quiet",
    layout: "left",
    block: "pill",
    enter: "zoom",
    sing: "none",
    exit: "dissolve",
    palette: "neon",
    burst: burst("crossette", [0, 1]),
    ornaments: [
      orn("dots-line", "line-end", "back", { density: 0.7, color: "accent" }),
      orn("glints", "glyphs", "front", { density: 0.5, color: "glow" }),
      orn("cross", "corners", "back", { density: 0.4, color: "paper" })
    ]
  },
  {
    kind: "hoshikuzu-veil",
    label: "\u661F\u5C51\xB7\u7EB1",
    mood: "quiet",
    layout: "stagger",
    block: "none",
    enter: "spiral",
    sing: "color",
    exit: "ascend",
    palette: "sakura",
    burst: burst("kamuro", [0, 1, 3], { count: 90 }),
    ornaments: [
      orn("sparkle", "glyphs", "front", { density: 0.6, color: "glow" }),
      orn("wave", "behind", "back", { density: 0.4, color: "accent" }),
      orn("orbit", "around", "back", { density: 0.35, color: "spark" })
    ]
  }
]);
var OBI = family("obi", {
  text: { heroSize: 0.09, emphasis: 0.4, tilt: 0, stagger: 0.04, outline: false, hardShadow: false },
  burstAt: "sides",
  sungBurst: null,
  launch: false,
  camera: { rise: 0.5, push: 0.02, roll: 0, punch: 0.2 }
}, [
  {
    kind: "obi-band",
    label: "\u5E2F\xB7\u6A2A\u5E26",
    mood: "neutral",
    layout: "left",
    block: "band",
    enter: "wipe",
    sing: "underline",
    exit: "slide",
    palette: "festival",
    burst: burst("ring", [0, 1]),
    ornaments: [
      orn("zigzag", "line-end", "back", { density: 0.6, color: "block" }),
      orn("chevrons", "line-start", "back", { density: 0.5, color: "accent" }),
      orn("underline", "glyphs", "front", { color: "paper" })
    ]
  },
  {
    kind: "obi-ticket",
    label: "\u5E2F\xB7\u7968\u636E",
    mood: "neutral",
    layout: "center",
    block: "ticket",
    enter: "flip",
    sing: "color",
    exit: "slide",
    palette: "pastel",
    burst: burst("botan", [0, 2], { count: 64 }),
    burstAt: "above",
    ornaments: [
      orn("brackets", "around", "back", { color: "accent" }),
      orn("dots-line", "line-end", "back", { density: 0.5, color: "paper" }),
      orn("stamp", "line-start", "front", { scale: 0.9, color: "accent", delay: 0.35 })
    ]
  },
  {
    kind: "obi-slant",
    label: "\u5E2F\xB7\u659C\u5757",
    mood: "loud",
    layout: "diagonal",
    block: "slant",
    enter: "wipe",
    sing: "underline",
    exit: "slide",
    palette: "neon",
    burst: burst("palm", [0, 1, 2]),
    text: { tilt: -0.14, hardShadow: true },
    ornaments: [
      orn("chevrons", "line-end", "front", { density: 0.7, color: "spark" }),
      orn("streaks", "screen", "back", { density: 0.5, color: "paper" }),
      orn("zigzag", "around", "back", { density: 0.5, color: "block" })
    ],
    camera: { punch: 0.45 }
  },
  {
    kind: "obi-marker",
    label: "\u5E2F\xB7\u8367\u5149\u7B14",
    mood: "neutral",
    layout: "stagger",
    block: "marker",
    enter: "type",
    sing: "underline",
    exit: "blink",
    palette: "ocean",
    burst: burst("star", [0, 1]),
    burstAt: "sky",
    ornaments: [
      orn("underline", "glyphs", "back", { scale: 1.2, color: "accent" }),
      orn("squares", "corners", "back", { density: 0.5, color: "block" }),
      orn("brackets", "around", "front", { scale: 1.1, color: "paper" })
    ]
  },
  {
    kind: "obi-stair",
    label: "\u5E2F\xB7\u9636\u68AF",
    mood: "neutral",
    layout: "right",
    block: "stair",
    enter: "stretch",
    sing: "jump",
    exit: "slide",
    palette: "gold",
    burst: burst("crossette", [0, 1, 3]),
    text: { hardShadow: true },
    ornaments: [
      orn("squares", "around", "back", { density: 0.55, color: "accent" }),
      orn("halftone", "behind", "back", { density: 0.5, color: "block" }),
      orn("chevrons", "line-start", "front", { density: 0.5, color: "paper" })
    ]
  }
]);
var SENKO = family("senko", {
  text: { heroSize: 0.1, emphasis: 0.5, tilt: 0, stagger: 0.025, outline: false, hardShadow: true },
  burstAt: "behind",
  sungBurst: null,
  launch: false,
  camera: { rise: 0.6, push: 0.06, roll: 0.015, punch: 0.7 }
}, [
  {
    kind: "senko-glitch",
    label: "\u9583\u5149\xB7\u6545\u969C",
    mood: "loud",
    layout: "center",
    block: "split",
    enter: "glitch",
    sing: "shake",
    exit: "blink",
    palette: "neon",
    burst: burst("strobe", [0, 1, 2, 3]),
    ornaments: [
      orn("streaks", "screen", "back", { density: 0.7, color: "spark" }),
      orn("shards", "around", "front", { density: 0.5, color: "block" }),
      orn("squares", "around", "back", { density: 0.5, color: "paper" })
    ]
  },
  {
    kind: "senko-scramble",
    label: "\u9583\u5149\xB7\u4E71\u7801",
    mood: "neutral",
    layout: "left",
    block: "outline",
    enter: "scramble",
    sing: "flash",
    exit: "blink",
    palette: "mono",
    burst: burst("hachi", [0, 1]),
    burstAt: "sides",
    text: { outline: true, hardShadow: false },
    ornaments: [
      orn("brackets", "around", "back", { color: "paper" }),
      orn("cross", "corners", "front", { density: 0.5, color: "accent" }),
      orn("streaks", "line-end", "back", { density: 0.5, color: "glow" })
    ],
    camera: { punch: 0.4 }
  },
  {
    kind: "senko-strobe",
    label: "\u9583\u5149\xB7\u9891\u95EA",
    mood: "loud",
    layout: "scatter",
    block: "tile",
    enter: "glitch",
    sing: "flash",
    exit: "scatter",
    palette: "kawaii",
    burst: burst("mine", [0, 1, 2]),
    burstAt: "sky",
    sungBurst: small("strobe", [0, 1], { count: 10, twinkle: 1 }),
    ornaments: [
      orn("streaks", "screen", "back", { density: 0.8, color: "paper" }),
      orn("zigzag", "around", "front", { density: 0.5, color: "accent" }),
      orn("glints", "glyphs", "front", { density: 0.5, color: "glow" })
    ]
  },
  {
    kind: "senko-stretch",
    label: "\u9583\u5149\xB7\u62C9\u4F38",
    mood: "loud",
    layout: "center",
    block: "slant",
    enter: "stretch",
    sing: "shake",
    exit: "shrink",
    palette: "neon",
    burst: burst("crossette", [0, 2, 3]),
    text: { tilt: -0.06 },
    ornaments: [
      orn("spokes", "around", "back", { density: 0.8, color: "paper" }),
      orn("streaks", "screen", "front", { density: 0.5, color: "spark" }),
      orn("shards", "around", "back", { density: 0.4, color: "block" })
    ]
  },
  {
    kind: "senko-type",
    label: "\u9583\u5149\xB7\u6253\u5B57",
    mood: "neutral",
    layout: "right",
    block: "ticket",
    enter: "scramble",
    sing: "none",
    exit: "blink",
    palette: "mono",
    burst: burst("ring", [0, 1], { count: 48 }),
    burstAt: "above",
    ornaments: [
      orn("dots-line", "line-start", "back", { density: 0.6, color: "paper" }),
      orn("brackets", "around", "front", { scale: 1.08, color: "accent" }),
      orn("cross", "screen", "back", { density: 0.35, color: "glow" })
    ],
    camera: { punch: 0.3, roll: 0 }
  }
]);
var SENKOHANABI = family("senkohanabi", {
  text: { heroSize: 0.08, emphasis: 0.2, tilt: 0, stagger: 0.08, outline: false, hardShadow: false },
  burstAt: "behind",
  sungBurst: small("hachi", [0, 1], { count: 12, radius: 0.035, duration: 0.6, trail: 0.4, twinkle: 0.8 }),
  launch: false,
  camera: { rise: 0.3, push: 0.02, roll: 4e-3, punch: 0 }
}, [
  {
    kind: "senkohanabi-hachi",
    label: "\u7DDA\u9999\xB7\u706B\u82B1",
    mood: "quiet",
    layout: "vertical",
    block: "none",
    enter: "type",
    sing: "glow",
    exit: "fall",
    palette: "gold",
    burst: burst("hachi", [0, 1], { count: 36, radius: 0.14 }),
    region: REGIONS.verticalRight,
    ornaments: [
      orn("glints", "glyphs", "front", { density: 0.6, color: "spark" }),
      orn("sparkle", "glyphs", "front", { density: 0.35, scale: 0.7, color: "glow" }),
      orn("dots-line", "glyphs", "back", { density: 0.4, scale: 0.7, color: "accent" })
    ]
  },
  {
    kind: "senkohanabi-tama",
    label: "\u7DDA\u9999\xB7\u706B\u7389",
    mood: "quiet",
    layout: "center",
    block: "none",
    enter: "split",
    sing: "glow",
    exit: "dissolve",
    palette: "night",
    burst: burst("botan", [0, 1], { count: 40, radius: 0.12, duration: 1.2 }),
    burstAt: "above",
    text: { heroSize: 0.085 },
    ornaments: [
      orn("glints", "glyphs", "front", { density: 0.5, color: "spark" }),
      orn("sparkle", "around", "front", { density: 0.3, scale: 0.7, color: "glow" })
    ]
  },
  {
    kind: "senkohanabi-matsuba",
    label: "\u7DDA\u9999\xB7\u677E\u8449",
    mood: "quiet",
    layout: "left",
    block: "circle",
    enter: "elastic",
    sing: "swell",
    exit: "dissolve",
    palette: "gold",
    burst: burst("crossette", [0, 1], { count: 28, radius: 0.15 }),
    burstAt: "sides",
    ornaments: [
      orn("sparkle", "glyphs", "front", { density: 0.45, color: "spark" }),
      orn("cross", "around", "back", { density: 0.35, scale: 0.7, color: "glow" })
    ]
  },
  {
    kind: "senkohanabi-chiri",
    label: "\u7DDA\u9999\xB7\u6563\u83CA",
    mood: "quiet",
    layout: "arc",
    block: "marker",
    enter: "flip",
    sing: "underline",
    exit: "fall",
    palette: "sakura",
    burst: burst("yanagi", [0, 1], { count: 40, radius: 0.18 }),
    burstAt: "above",
    ornaments: [
      orn("petals", "screen", "front", { density: 0.35, color: "block" }),
      orn("glints", "glyphs", "front", { density: 0.4, color: "paper" })
    ]
  },
  {
    kind: "senkohanabi-tsubomi",
    label: "\u7DDA\u9999\xB7\u857E",
    mood: "quiet",
    layout: "vertical-split",
    block: "none",
    enter: "split",
    sing: "glow",
    exit: "fall",
    palette: "kawaii",
    burst: burst("strobe", [0, 1], { count: 30, radius: 0.14 }),
    ornaments: [
      orn("dots-line", "glyphs", "back", { density: 0.5, color: "spark" }),
      orn("glints", "glyphs", "front", { density: 0.5, color: "glow" }),
      orn("dash-circle", "behind", "back", { scale: 0.9, density: 0.4, color: "paper" })
    ]
  }
]);
var SHAKUDAMA = family("shakudama", {
  text: { heroSize: 0.19, emphasis: 0.25, tilt: 0, stagger: 0.06, outline: true, hardShadow: true },
  burstAt: "behind",
  sungBurst: null,
  launch: true,
  camera: { rise: 0.85, push: 0.09, roll: 0, punch: 0.9 }
}, [
  {
    kind: "shakudama-kamuro",
    label: "\u5C3A\u7389\xB7\u91D1\u51A0",
    mood: "loud",
    layout: "center",
    block: "none",
    enter: "stamp",
    sing: "none",
    exit: "shrink",
    palette: "gold",
    burst: burst("kamuro", [0, 1, 2], { count: 160, radius: 0.48, duration: 4.2 }),
    region: REGIONS.giant,
    ornaments: [
      orn("rays", "behind", "back", { density: 0.8, scale: 1.5, color: "glow" }),
      orn("ring", "behind", "back", { density: 0.6, scale: 1.6, color: "accent", delay: 0.1 }),
      orn("spokes", "around", "front", { density: 0.5, scale: 1.3, color: "paper" })
    ]
  },
  {
    kind: "shakudama-nishiki",
    label: "\u5C3A\u7389\xB7\u9526",
    mood: "loud",
    layout: "center",
    block: "double",
    enter: "zoom",
    sing: "swell",
    exit: "scatter",
    palette: "festival",
    burst: burst("willow-ring", [0, 1, 2, 3], { count: 150, radius: 0.46 }),
    region: REGIONS.giant,
    text: { heroSize: 0.17 },
    ornaments: [
      orn("rays", "behind", "back", { density: 0.6, scale: 1.4, color: "block" }),
      orn("stamp", "line-end", "front", { scale: 1.2, color: "accent", delay: 0.4 }),
      orn("ring", "around", "back", { density: 0.7, scale: 1.3, color: "spark" })
    ]
  },
  {
    kind: "shakudama-asahi",
    label: "\u5C3A\u7389\xB7\u65ED\u65E5",
    mood: "loud",
    layout: "center",
    block: "circle",
    enter: "burst",
    sing: "flash",
    exit: "shrink",
    palette: "festival",
    burst: burst("kamuro", [1, 0], { count: 140, radius: 0.44 }),
    region: REGIONS.giant,
    ornaments: [
      orn("rays", "behind", "back", { density: 0.9, scale: 1.6, color: "block" }),
      orn("spokes", "behind", "back", { density: 0.6, scale: 1.4, color: "paper" }),
      orn("confetti", "screen", "front", { density: 0.5, color: "spark", delay: 0.2 })
    ]
  },
  {
    kind: "shakudama-heart",
    label: "\u5C3A\u7389\xB7\u5FC3",
    mood: "loud",
    layout: "center",
    block: "tile",
    enter: "stretch",
    sing: "jump",
    exit: "scatter",
    palette: "sakura",
    burst: burst("heart", [0, 1, 3], { count: 110, radius: 0.36 }),
    region: REGIONS.giant,
    text: { heroSize: 0.17 },
    ornaments: [
      orn("stamp", "line-start", "front", { scale: 1.3, color: "accent", delay: 0.3 }),
      orn("rays", "behind", "back", { density: 0.5, scale: 1.3, color: "glow" }),
      orn("confetti", "screen", "front", { density: 0.55, color: "block" })
    ]
  },
  {
    kind: "shakudama-mine",
    label: "\u5C3A\u7389\xB7\u901F\u5C04",
    mood: "loud",
    layout: "left",
    block: "split",
    enter: "stamp",
    sing: "shake",
    exit: "scatter",
    palette: "neon",
    burst: burst("mine", [0, 1, 2, 3], { count: 120 }),
    burstAt: "sky",
    region: REGIONS.giantLeft,
    text: { heroSize: 0.16, tilt: -0.05 },
    ornaments: [
      orn("streaks", "screen", "back", { density: 0.8, color: "spark" }),
      orn("shards", "around", "front", { density: 0.6, color: "block" }),
      orn("rays", "behind", "back", { density: 0.5, scale: 1.3, color: "accent" })
    ]
  }
]);
var HANABI_PROFILES = [
  ...UCHIAGE,
  ...KIKU,
  ...BOTAN,
  ...YANAGI,
  ...SENRIN,
  ...HOSHIKUZU,
  ...OBI,
  ...SENKO,
  ...SENKOHANABI,
  ...SHAKUDAMA
];
var BY_KIND2 = new Map(HANABI_PROFILES.map((profile) => [profile.kind, profile]));
var HANABI_KINDS = HANABI_PROFILES.map((profile) => profile.kind);
var profileOf2 = (kind) => BY_KIND2.get(kind) ?? HANABI_PROFILES[0];

// folia:src/components/visualizer/lucidePath2d.ts
var lucideIconPath2d = (node2, into = new Path2D()) => {
  node2.forEach((entry) => {
    const [tag, attrs, children] = entry;
    const n = (key, fallback = 0) => {
      const value = Number.parseFloat(String(attrs[key] ?? ""));
      return Number.isFinite(value) ? value : fallback;
    };
    if (tag === "path" && typeof attrs.d === "string") into.addPath(new Path2D(attrs.d));
    else if (tag === "circle") {
      into.moveTo(n("cx") + n("r"), n("cy"));
      into.arc(n("cx"), n("cy"), n("r"), 0, Math.PI * 2);
    } else if (tag === "ellipse") {
      into.moveTo(n("cx") + n("rx"), n("cy"));
      into.ellipse(n("cx"), n("cy"), n("rx"), n("ry"), 0, 0, Math.PI * 2);
    } else if (tag === "rect") {
      into.roundRect(n("x"), n("y"), n("width"), n("height"), Math.min(n("rx", n("ry")), n("width") / 2, n("height") / 2));
    } else if (tag === "line") {
      into.moveTo(n("x1"), n("y1"));
      into.lineTo(n("x2"), n("y2"));
    } else if (tag === "polyline" || tag === "polygon") {
      const numbers = String(attrs.points ?? "").trim().split(/[\s,]+/).map(Number).filter(Number.isFinite);
      for (let i = 0; i + 1 < numbers.length; i += 2) {
        if (i === 0) into.moveTo(numbers[i], numbers[i + 1]);
        else into.lineTo(numbers[i], numbers[i + 1]);
      }
      if (tag === "polygon") into.closePath();
    }
    if (Array.isArray(children)) lucideIconPath2d(children, into);
  });
  return into;
};

// folia:src/components/visualizer/hanabi/hanabiRandom.ts
var createRng2 = createVisualizerRng;

// folia:src/components/visualizer/hanabi/mg/mgMath.ts
var TAU2 = Math.PI * 2;
var clamp017 = (value) => value <= 0 ? 0 : value >= 1 ? 1 : value;
var clamp3 = (value, low, high) => value < low ? low : value > high ? high : value;
var lerp3 = (a, b, t) => a + (b - a) * t;
var fract2 = (value) => value - Math.floor(value);
var wrap2 = (value, span) => value - span * Math.floor(value / span);
var easeOutCubic3 = (t) => 1 - (1 - clamp017(t)) ** 3;
var easeInCubic = (t) => clamp017(t) ** 3;
var easeOutExpo2 = (t) => {
  const x = clamp017(t);
  return x >= 1 ? 1 : 1 - 2 ** (-10 * x);
};
var easeOutBack = (t, overshoot = 1.70158) => {
  const x = clamp017(t) - 1;
  return 1 + x * x * ((overshoot + 1) * x + overshoot);
};
var easeInBack = (t, overshoot = 1.70158) => {
  const x = clamp017(t);
  return x * x * ((overshoot + 1) * x - overshoot);
};
var spring = (seconds, freq = 2.6, decay = 7) => seconds <= 0 ? 0 : 1 - Math.exp(-decay * seconds) * Math.cos(TAU2 * freq * seconds);
var beatSteps = (beats, snap = 0.35) => {
  const whole = Math.floor(beats);
  return whole + easeOutBack(fract2(beats) / snap, 2.2);
};
var hash01 = (n, salt = 0) => fract2(Math.sin(n * 127.1 + salt * 311.7) * 43758.5453123);
var hashString = (key) => {
  let hash = 2166136261;
  for (let i = 0; i < key.length; i += 1) {
    hash ^= key.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
};
var mixColor = (a, b, t) => {
  const k = clamp017(t);
  if (k <= 0) return a;
  if (k >= 1) return b;
  const r = Math.round((a >> 16 & 255) + ((b >> 16 & 255) - (a >> 16 & 255)) * k);
  const g = Math.round((a >> 8 & 255) + ((b >> 8 & 255) - (a >> 8 & 255)) * k);
  const bl = Math.round((a & 255) + ((b & 255) - (a & 255)) * k);
  return r << 16 | g << 8 | bl;
};
var WHITE2 = 16777215;
var GOLD = 16762720;
var EMBER = 16751164;

// folia:src/components/visualizer/hanabi/collage/collagePlan.ts
var FAMILY_RECIPES = {
  uchiage: ["strips", "scrapbook", "stickerbomb"],
  kiku: ["echo", "strips", "window"],
  botan: ["stickerbomb", "scrapbook", "window"],
  yanagi: ["quiet", "echo"],
  senrin: ["stickerbomb", "strips", "scrapbook"],
  hoshikuzu: ["window", "quiet", "stickerbomb"],
  obi: ["strips", "scrapbook", "echo"],
  senko: ["window", "echo", "strips"],
  senkohanabi: ["quiet", "scrapbook"],
  shakudama: ["echo", "strips", "stickerbomb"]
};
var CANDY = [16757713, 12120806, 16773544, 14140671, 16763304, 11066623];
var CANDY_INK = 2826045;
var DEEP_CARD = 1906744;
var HANABI_FALLBACK_ICON = "Flower";
var ICON_INKS = [16736162, 4174591, 16753434, 10185727, 3066272];
var BUBBLE_LABELS = ["\u2661", "!!", "\u266A", "LOVE", "yay!", "(\u2267\u25BD\u2266)", "\u2606\u5F61"];
var WINDOW_TITLES = ["\u2661 hanabi.exe", "\u266A lyric.txt", "\u2726 night_sky.png", "\u2606 summer.mp3", "\u2661 kirakira.app"];
var SHAPES = ["heart", "star", "sparkle", "flower", "cloud", "ribbon", "cat"];
var STRIP_STYLES = ["film", "cut", "lace"];
var STRIP_THICKNESS = { film: 0.075, cut: 0.045, lace: 0.06 };
var pick = (list, random) => list[Math.floor(random() * list.length) % list.length];
var pastel = (color, amount = 0.45) => mixColor(color, 16777215, amount);
var LATIN = /^[\p{Script=Latin}\p{N}'’\- ]+$/u;
var pickCollageKeyword = (line2) => {
  if (!line2) return null;
  const text = line2.fullText.trim();
  const graphemes = splitLyricGraphemes(text).filter((grapheme) => grapheme.trim().length > 0);
  const shout = (word) => LATIN.test(word) ? word.toLocaleUpperCase() : word;
  if (graphemes.length >= 2 && graphemes.length <= 5) return shout(text);
  let best = null;
  let bestLength = 0;
  segmentLyricWords(line2).forEach((part) => {
    const word = part.segment.trim();
    const length = splitLyricGraphemes(word).length;
    if (!part.isWordLike || length < 2 || length > 10) return;
    if (length > bestLength) {
      best = word;
      bestLength = length;
    }
  });
  return best ? shout(best) : null;
};
var chooseCollageRecipe = (family2, isBridge, previous, random) => {
  if (isBridge) return "bridge";
  const preferred = FAMILY_RECIPES[family2] ?? ["scrapbook", "strips", "stickerbomb"];
  const choices = preferred.filter((recipe) => recipe !== previous);
  const list = choices.length > 0 ? choices : preferred;
  const total = list.length * (list.length + 1) / 2;
  let roll = random() * total;
  for (let index = 0; index < list.length; index += 1) {
    roll -= list.length - index;
    if (roll < 0) return list[index];
  }
  return list[0];
};
var countOf = (base, amount, min = 1) => amount <= 0 ? 0 : Math.max(min, Math.round(base * amount));
var planShotCollage = (input) => {
  if (input.amount <= 0) return { recipe: null, items: [] };
  const random = createRng2(`${input.seed}:collage`);
  const recipe = input.isBridge && input.opening ? "opening" : chooseCollageRecipe(input.family, input.isBridge, input.previous, random);
  const { bounds, screen, unit, amount } = input;
  const items = [];
  const exit = { exitAt: input.exitAt, exitDuration: input.exitDuration };
  const candy = [...CANDY, pastel(input.palette.accent), pastel(input.palette.sparks[1] ?? input.palette.accent)];
  const candyColor = () => pick(candy, random);
  const railGap = unit * 0.14;
  const cx = bounds.x + bounds.width / 2;
  const cy = bounds.y + bounds.height / 2;
  const sx = screen.x + screen.width / 2;
  const clampX = (x, pad) => clamp3(x, screen.x + railGap * 0.5 + pad, screen.x + screen.width - pad);
  const clampY = (y, pad) => clamp3(y, screen.y + pad, screen.y + screen.height - pad);
  const signed = () => random() < 0.5 ? -1 : 1;
  const motifs = input.motifs.length > 0 ? input.motifs : ["HANABI", "\u82B1\u706B"];
  const motif = () => pick(motifs, random);
  const sticker = (shape, x, y, size, delay, layer = "front", label2 = null) => ({
    kind: "sticker",
    shape,
    x: clampX(x, size * 0.6),
    y: clampY(y, size * 0.6),
    size,
    rotation: (random() - 0.5) * 0.7,
    color: candyColor(),
    label: label2,
    layer,
    at: input.enterAt + delay,
    ...exit
  });
  const corner = (index, out) => {
    const dx = index === 0 || index === 3 ? -1 : 1;
    const dy = index < 2 ? -1 : 1;
    return {
      x: (dx < 0 ? bounds.x : bounds.x + bounds.width) + dx * out,
      y: (dy < 0 ? bounds.y : bounds.y + bounds.height) + dy * out * 0.6
    };
  };
  const strip = (style, side, delay) => {
    const thickness = Math.max(style === "cut" ? 14 : 18, unit * STRIP_THICKNESS[style]);
    const gap = unit * 0.05 + thickness / 2;
    let y = side < 0 ? bounds.y - gap : bounds.y + bounds.height + gap;
    y = clampY(y, thickness);
    return {
      kind: "strip",
      style,
      x: sx,
      y,
      length: Math.hypot(screen.width, screen.height) * 1.25,
      thickness,
      rotation: side * (0.06 + random() * 0.1),
      color: candyColor(),
      speed: signed() * unit * (style === "film" ? 0.12 : 0.05) * (0.8 + random() * 0.4),
      from: signed(),
      at: input.enterAt + delay,
      ...exit
    };
  };
  const echo = (axis, side, alpha) => {
    const text = input.keyword ?? motif();
    if (!text.trim()) return null;
    const size = unit * (axis === "x" ? 0.13 : 0.11);
    if (axis === "x") {
      const y = side < 0 ? bounds.y - size * 0.75 : bounds.y + bounds.height + size * 0.75;
      return {
        kind: "echo",
        axis,
        text,
        size,
        alpha,
        x: sx,
        y: clampY(y, size * 0.5),
        width: screen.width * 1.3,
        height: size * 1.25,
        rotation: (random() - 0.5) * 0.08,
        color: random() < 0.5 ? input.palette.paper : candyColor(),
        speed: side * unit * 0.07,
        at: input.enterAt - 0.15,
        ...exit
      };
    }
    const width = size * Math.max(1, Array.from(text).length) * 0.9 + size * 0.4;
    const free = (screen.width - bounds.width) / 2;
    const x = side < 0 ? bounds.x - width * 0.55 : bounds.x + bounds.width + width * 0.55;
    return {
      kind: "echo",
      axis,
      text,
      size,
      alpha,
      // 两侧放不下就贴在画面边上（在字后面，淡）；左边让开竖排跑马灯与画框的朱印。
      x: clamp3(free > width * 0.6 ? x : side < 0 ? -Infinity : Infinity, screen.x + railGap + width * 0.5, screen.x + screen.width - unit * 0.06 - width * 0.5),
      y: cy,
      width,
      height: screen.height * 1.3,
      rotation: 0,
      color: random() < 0.5 ? input.palette.paper : candyColor(),
      speed: side * unit * 0.06,
      at: input.enterAt - 0.15,
      ...exit
    };
  };
  const patch = (pad, offset, pattern, delay) => {
    const dark = input.block === "none" || input.block === "outline" || input.block === "marker";
    return {
      kind: "patch",
      x: cx + offset * signed(),
      y: cy + offset * signed() * 0.6,
      width: bounds.width + pad * 2,
      height: bounds.height + pad * 2,
      rotation: (random() - 0.5) * 0.09,
      color: dark ? DEEP_CARD : candyColor(),
      pattern,
      dark,
      at: input.enterAt + delay,
      ...exit
    };
  };
  const tape = (index, delay, around) => {
    const length = unit * (0.12 + random() * 0.04);
    const x = index === 0 || index === 3 ? around.x : around.x + around.width;
    const y = index < 2 ? around.y : around.y + around.height;
    const diagonal = index === 0 || index === 2 ? -1 : 1;
    return {
      kind: "tape",
      x,
      y,
      length,
      width: length * 0.3,
      rotation: diagonal * (0.62 + random() * 0.2),
      color: candyColor(),
      pattern: pick(["stripe", "dot", "check"], random),
      at: input.enterAt + delay,
      ...exit
    };
  };
  const label = (delay) => {
    const size = Math.max(12, unit * 0.026);
    const text = random() < 0.5 ? `No.${String(input.shotNumber + 1).padStart(2, "0")}` : `#${String(input.shotNumber + 1).padStart(2, "0")} ${pick(["\u266A", "\u2661", "\u2726"], random)}`;
    const at = corner(3, size * 0.4);
    return {
      kind: "label",
      x: clampX(at.x + size * 2.2, size * 3),
      y: clampY(at.y + size * 0.9, size),
      text,
      color: candyColor(),
      size,
      rotation: (random() - 0.5) * 0.2,
      at: input.enterAt + delay,
      ...exit
    };
  };
  const stickerSize = () => unit * (0.065 + random() * 0.04);
  switch (recipe) {
    case "scrapbook": {
      const pad = unit * 0.045;
      const card = patch(pad, unit * 0.012, pick(["grid", "dots", "gingham"], random), -0.12);
      items.push(patch(pad * 0.6, unit * 0.04, "plain", -0.2), card);
      const around = { x: card.x - card.width / 2, y: card.y - card.height / 2, width: card.width, height: card.height };
      const first = Math.floor(random() * 2);
      items.push(tape(first, 0.05, around), tape(first + 2, 0.12, around));
      for (let k = 0; k < countOf(1.5, amount); k += 1) {
        const at = corner((first + 1 + k * 2) % 4, unit * 0.03);
        items.push(sticker(pick(SHAPES, random), at.x, at.y, stickerSize(), 0.25 + k * 0.1));
      }
      items.push(label(0.3));
      break;
    }
    case "strips": {
      const side = random() < 0.5 ? -1 : 1;
      const first = pick(STRIP_STYLES, random);
      items.push(strip(first, side, -0.1));
      if (amount >= 0.75) items.push(strip(pick(STRIP_STYLES.filter((style) => style !== first), random), side === -1 ? 1 : -1, 0.05));
      for (let k = 0; k < countOf(2, amount); k += 1) {
        const at = corner((k * 2 + (side < 0 ? 1 : 0)) % 4, unit * 0.04);
        items.push(sticker(k % 2 === 0 ? "sparkle" : "star", at.x, at.y, stickerSize() * 0.85, 0.2 + k * 0.12));
      }
      break;
    }
    case "echo": {
      const vertical = screen.width - bounds.width > unit * 0.5;
      const first = echo(vertical ? "y" : "x", -1, 0.3);
      const second = echo(vertical ? "y" : "x", 1, 0.3);
      if (first) items.push(first);
      if (second && amount >= 0.75) items.push(second);
      const at = corner(1, unit * 0.04);
      items.push(sticker("bubble", at.x, at.y, stickerSize() * 1.6, 0.3, "front", pick(BUBBLE_LABELS, random)));
      break;
    }
    case "window": {
      const pad = unit * 0.05;
      const bar = Math.max(16, unit * 0.04);
      const width = bounds.width + pad * 2;
      const height = bounds.height + pad * 2 + bar;
      const win = {
        kind: "window",
        x: cx,
        y: cy - bar / 2,
        width,
        height,
        rotation: (random() - 0.5) * 0.05,
        bar,
        title: pick(WINDOW_TITLES, random),
        at: input.enterAt - 0.18,
        ...exit
      };
      items.push(win);
      for (let k = 0; k < countOf(2, amount); k += 1) {
        const at = corner(k === 0 ? 0 : 2, unit * 0.035);
        items.push(sticker(pick(SHAPES, random), at.x, at.y, stickerSize(), 0.25 + k * 0.12));
      }
      break;
    }
    case "stickerbomb": {
      const count = countOf(4, amount, 2);
      for (let k = 0; k < count; k += 1) {
        const at2 = corner(k % 4, unit * (0.03 + 0.03 * Math.floor(k / 4)));
        const jitter = unit * 0.03;
        items.push(sticker(pick(SHAPES, random), at2.x + (random() - 0.5) * jitter, at2.y + (random() - 0.5) * jitter, stickerSize(), 0.15 + k * 0.08));
      }
      const at = corner(Math.floor(random() * 4), unit * 0.09);
      items.push(sticker("bubble", at.x, at.y, stickerSize() * 1.5, 0.4, "front", pick(BUBBLE_LABELS, random)));
      break;
    }
    case "quiet": {
      const row = echo("x", random() < 0.5 ? -1 : 1, 0.16);
      if (row) items.push(row);
      const at = corner(Math.floor(random() * 4), unit * 0.03);
      items.push(sticker("sparkle", at.x, at.y, stickerSize() * 0.7, 0.35));
      break;
    }
    case "opening": {
      const opening = input.opening;
      const leave2 = { exitAt: Math.max(input.start + 1.2, input.end - 0.7), exitDuration: 0.5 };
      const titleSize = Math.min(unit * 0.11, screen.width * 0.5 / Math.max(4, Array.from(opening.title).length * 0.62));
      const width = Math.min(screen.width * 0.72, Math.max(unit * 0.6, titleSize * Array.from(opening.title).length * 0.7 + unit * 0.2));
      const bar = Math.max(16, unit * 0.045);
      const height = titleSize * 1.9 + bar + (opening.artist ? unit * 0.06 : 0);
      const y = screen.y + screen.height * 0.42;
      const at = input.start + 0.25;
      items.push({
        kind: "window",
        x: sx,
        y,
        width,
        height,
        rotation: -0.02,
        bar,
        title: "\u266A now playing",
        at,
        ...leave2
      }, {
        kind: "headline",
        x: sx,
        y: y + bar / 2 - (opening.artist ? unit * 0.02 : 0),
        text: opening.title,
        color: candyColor(),
        size: titleSize,
        rotation: -0.03,
        at: at + 0.18,
        ...leave2
      });
      if (opening.artist) {
        items.push({
          kind: "label",
          x: sx,
          y: y + height / 2 - unit * 0.045,
          text: opening.artist,
          color: candyColor(),
          size: Math.max(12, unit * 0.028),
          rotation: 0.02,
          at: at + 0.4,
          ...leave2
        });
      }
      const card = { x: sx - width / 2, y: y - height / 2, width, height };
      [0, 1, 2, 3].forEach((k) => {
        const x = k === 0 || k === 3 ? card.x : card.x + card.width;
        const cornerY = k < 2 ? card.y : card.y + card.height;
        items.push({ ...sticker(pick(["heart", "star", "ribbon", "sparkle"], random), x, cornerY, unit * 0.075, 0), at: at + 0.3 + k * 0.08, ...leave2 });
      });
      const floaters = countOf(5, amount, 2);
      for (let k = 0; k < floaters; k += 1) {
        items.push({
          kind: "floater",
          shape: pick(["heart", "star", "sparkle"], random),
          x: screen.x + screen.width * (0.1 + random() * 0.8),
          y: screen.y + screen.height * 1.08,
          rise: screen.height * (1.25 + random() * 0.3),
          size: unit * (0.045 + random() * 0.04),
          color: candyColor(),
          at: input.start + 0.6 + k / floaters * Math.max(0.5, input.end - input.start - 1.5),
          duration: 3.4 + random() * 1.4,
          sway: unit * (0.02 + random() * 0.03)
        });
      }
      break;
    }
    case "bridge": {
      const film = strip("film", 1, 0);
      film.y = screen.y + screen.height * (0.62 + random() * 0.12);
      film.at = input.start + 0.1;
      items.push(film);
      const floaters = countOf(7, amount, 3);
      const span = Math.max(0.5, input.end - input.start);
      for (let k = 0; k < floaters; k += 1) {
        const at = input.start + k / floaters * span * 0.8 + random() * 0.3;
        items.push({
          kind: "floater",
          shape: pick(["heart", "star", "sparkle", "flower"], random),
          x: screen.x + screen.width * (0.08 + random() * 0.84),
          y: screen.y + screen.height * 1.08,
          rise: screen.height * (1.25 + random() * 0.3),
          size: unit * (0.05 + random() * 0.05),
          color: candyColor(),
          at,
          duration: 3.2 + random() * 1.6,
          sway: unit * (0.02 + random() * 0.03)
        });
      }
      break;
    }
  }
  const icons2 = input.icons && input.icons.length > 0 ? input.icons : [HANABI_FALLBACK_ICON];
  let iconTurn = Math.floor(random() * icons2.length);
  const nextIcon = () => icons2[iconTurn++ % icons2.length];
  const mains = input.bursts.filter((burst2) => burst2.main);
  const popped = recipe === "opening" ? [] : input.isBridge ? mains.filter((_, index) => index % 2 === 0).slice(0, 5) : mains.slice(0, 1);
  popped.forEach((burst2) => {
    if (random() > Math.min(1, 0.55 + 0.35 * amount)) return;
    const size = unit * (input.isBridge ? 0.1 : 0.115) * (0.9 + random() * 0.25);
    const view = input.screenAt?.(burst2.at + 0.35) ?? screen;
    const halfWidth = size * 0.6;
    const left = view.x + railGap * 0.5 + halfWidth;
    const right = view.x + view.width - halfWidth - size * 0.3;
    const top = view.y + size * 0.8;
    const bottom = view.y + view.height * 0.8;
    const preferRight = input.isBridge ? burst2.x > sx : burst2.x >= cx;
    const beside = (dir) => ({ x: dir > 0 ? bounds.x + bounds.width + halfWidth + size * 0.3 : bounds.x - halfWidth - size * 0.3, y: bounds.y + size * 0.2 });
    const candidates = input.isBridge ? [{ x: burst2.x + (preferRight ? 1 : -1) * burst2.radius * 0.45, y: burst2.y - burst2.radius * 0.35 }] : [beside(preferRight ? 1 : -1), beside(preferRight ? -1 : 1), { x: cx + (random() - 0.5) * bounds.width * 0.3, y: bounds.y - size * 0.75 }];
    const fits = (p) => p.x >= left && p.x <= right && p.y >= top && p.y <= bottom;
    const spot = candidates.find(fits) ?? candidates[0];
    items.push({
      kind: "pop",
      icon: nextIcon(),
      x: clamp3(spot.x, left, Math.max(left, right)),
      y: clamp3(spot.y, top, Math.max(top, bottom)),
      color: pick(ICON_INKS, random),
      size,
      rotation: (preferRight ? 1 : -1) * (0.08 + random() * 0.18),
      at: burst2.at + 0.04,
      duration: 1.3
    });
  });
  input.launches.slice(0, 2).forEach((launch2) => {
    if (random() > 0.45 + 0.25 * amount) return;
    items.push({
      kind: "whoosh",
      icon: nextIcon(),
      fromX: launch2.fromX,
      fromY: launch2.fromY,
      toX: launch2.toX,
      toY: launch2.toY,
      at: launch2.at,
      duration: launch2.duration,
      color: pick(ICON_INKS, random),
      size: Math.max(18, unit * 0.055)
    });
  });
  return { recipe, items };
};

// folia:src/components/visualizer/hanabi/collage/collagePainters.ts
var POP_FONT_FAMILIES = '"M PLUS Rounded 1c", "Zen Maru Gothic", "Kosugi Maru", "Hiragino Maru Gothic ProN", "Arial Rounded MT Bold", "Yu Gothic UI", "Meiryo UI", "Microsoft YaHei UI"';
var css = (color, alpha = 1) => `rgba(${color >> 16 & 255},${color >> 8 & 255},${color & 255},${alpha})`;
var STICKER_PX = 112;
var pathHeart = (context, c, r) => {
  context.moveTo(c, c + r * 0.85);
  context.bezierCurveTo(c - r * 1.25, c + r * 0.05, c - r * 0.95, c - r * 0.95, c, c - r * 0.42);
  context.bezierCurveTo(c + r * 0.95, c - r * 0.95, c + r * 1.25, c + r * 0.05, c, c + r * 0.85);
};
var pathStar = (context, c, r, points, inner, rotation = -Math.PI / 2) => {
  for (let i = 0; i < points * 2; i += 1) {
    const radius = i % 2 === 0 ? r : r * inner;
    const angle = rotation + i * Math.PI / points;
    const x = c + Math.cos(angle) * radius;
    const y = c + Math.sin(angle) * radius;
    if (i === 0) context.moveTo(x, y);
    else context.lineTo(x, y);
  }
  context.closePath();
};
var pathSparkle = (context, c, r) => {
  const pinch = r * 0.16;
  context.moveTo(c, c - r);
  context.quadraticCurveTo(c + pinch, c - pinch, c + r, c);
  context.quadraticCurveTo(c + pinch, c + pinch, c, c + r);
  context.quadraticCurveTo(c - pinch, c + pinch, c - r, c);
  context.quadraticCurveTo(c - pinch, c - pinch, c, c - r);
  context.closePath();
};
var pathFlower = (context, c, r) => {
  for (let i = 0; i < 5; i += 1) {
    const angle = -Math.PI / 2 + i * Math.PI * 2 / 5;
    context.moveTo(c + Math.cos(angle) * r * 0.55 + r * 0.42, c + Math.sin(angle) * r * 0.55);
    context.arc(c + Math.cos(angle) * r * 0.55, c + Math.sin(angle) * r * 0.55, r * 0.42, 0, Math.PI * 2);
  }
};
var pathCloud = (context, c, r) => {
  const bumps = [[-0.5, 0.15, 0.38], [-0.12, -0.18, 0.48], [0.38, -0.02, 0.42], [0.62, 0.25, 0.28], [0.05, 0.3, 0.4]];
  bumps.forEach(([dx, dy, k]) => {
    context.moveTo(c + dx * r + k * r, c + dy * r);
    context.arc(c + dx * r, c + dy * r, k * r, 0, Math.PI * 2);
  });
};
var pathRibbon = (context, c, r) => {
  context.moveTo(c, c);
  context.bezierCurveTo(c - r * 0.5, c - r * 0.75, c - r * 1.05, c - r * 0.55, c - r * 0.95, c);
  context.bezierCurveTo(c - r * 1.05, c + r * 0.55, c - r * 0.5, c + r * 0.75, c, c);
  context.bezierCurveTo(c + r * 0.5, c - r * 0.75, c + r * 1.05, c - r * 0.55, c + r * 0.95, c);
  context.bezierCurveTo(c + r * 1.05, c + r * 0.55, c + r * 0.5, c + r * 0.75, c, c);
  context.moveTo(c + r * 0.24, c);
  context.arc(c, c, r * 0.24, 0, Math.PI * 2);
};
var pathCat = (context, c, r) => {
  context.moveTo(c + r * 0.78, c + r * 0.12);
  context.arc(c, c + r * 0.12, r * 0.78, 0, Math.PI * 2);
  context.moveTo(c - r * 0.72, c - r * 0.2);
  context.lineTo(c - r * 0.62, c - r * 0.95);
  context.lineTo(c - r * 0.12, c - r * 0.6);
  context.closePath();
  context.moveTo(c + r * 0.72, c - r * 0.2);
  context.lineTo(c + r * 0.62, c - r * 0.95);
  context.lineTo(c + r * 0.12, c - r * 0.6);
  context.closePath();
};
var pathBubble = (context, c, r) => {
  const w = r * 1;
  const h = r * 0.72;
  const top = c - h * 0.95;
  const radius = h * 0.55;
  context.roundRect(c - w, top, w * 2, h * 1.6, radius);
  context.moveTo(c - w * 0.35, top + h * 1.55);
  context.lineTo(c - w * 0.62, top + h * 2.15);
  context.lineTo(c - w * 0.02, top + h * 1.55);
  context.closePath();
};
var SHAPE_PATHS = {
  heart: pathHeart,
  star: (context, c, r) => pathStar(context, c, r, 5, 0.48),
  sparkle: pathSparkle,
  flower: pathFlower,
  cloud: pathCloud,
  ribbon: pathRibbon,
  cat: pathCat,
  bubble: pathBubble
};
var popFont = (px, fallback) => `800 ${px}px ${POP_FONT_FAMILIES}, ${fallback}`;
var createCollageTextureCache = (pixi, resolution, fallbackFont) => {
  const scale = Math.max(1, Math.min(2, resolution || 1));
  const cache2 = /* @__PURE__ */ new Map();
  const measureContext2 = document.createElement("canvas").getContext("2d");
  const canvasOf3 = (width, height) => {
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.ceil(width * scale));
    canvas.height = Math.max(1, Math.ceil(height * scale));
    const context = canvas.getContext("2d");
    context.setTransform(scale, 0, 0, scale, 0, 0);
    return { canvas, context };
  };
  const finish = (key, canvas) => {
    const source = new pixi.CanvasSource({ resource: canvas, resolution: scale });
    const texture = new pixi.Texture({ source });
    cache2.set(key, texture);
    return texture;
  };
  const cached = (key, paint) => cache2.get(key) ?? finish(key, paint());
  const measure = (text, font) => {
    measureContext2.font = font;
    return measureContext2.measureText(text).width;
  };
  const sticker = (shape, color, label2) => cached(`sticker:${shape}:${color}:${label2 ?? ""}`, () => {
    const side = STICKER_PX;
    const { canvas, context } = canvasOf3(side, side);
    const c = side / 2;
    const r = side * 0.34;
    const path2 = SHAPE_PATHS[shape];
    context.lineJoin = "round";
    context.lineCap = "round";
    context.save();
    context.translate(side * 0.035, side * 0.05);
    context.beginPath();
    path2(context, c, r);
    context.lineWidth = side * 0.13;
    context.strokeStyle = "rgba(30,16,48,0.28)";
    context.fillStyle = "rgba(30,16,48,0.28)";
    context.stroke();
    context.fill();
    context.restore();
    context.beginPath();
    path2(context, c, r);
    context.lineWidth = side * 0.13;
    context.strokeStyle = "#ffffff";
    context.fillStyle = "#ffffff";
    context.stroke();
    context.fill();
    context.beginPath();
    path2(context, c, r);
    context.fillStyle = css(color);
    context.fill();
    context.save();
    context.beginPath();
    path2(context, c, r);
    context.clip();
    context.fillStyle = "rgba(255,255,255,0.4)";
    context.beginPath();
    context.ellipse(c - r * 0.35, c - r * 0.4, r * 0.28, r * 0.16, -0.6, 0, Math.PI * 2);
    context.fill();
    context.restore();
    if (shape === "cat") {
      context.fillStyle = css(2826045);
      context.beginPath();
      context.arc(c - r * 0.3, c + r * 0.08, r * 0.08, 0, Math.PI * 2);
      context.arc(c + r * 0.3, c + r * 0.08, r * 0.08, 0, Math.PI * 2);
      context.fill();
      context.strokeStyle = css(2826045);
      context.lineWidth = r * 0.07;
      context.beginPath();
      context.arc(c - r * 0.09, c + r * 0.28, r * 0.09, 0.1, Math.PI - 0.1);
      context.arc(c + r * 0.09, c + r * 0.28, r * 0.09, 0.1, Math.PI - 0.1);
      context.stroke();
      context.fillStyle = "rgba(255,120,160,0.55)";
      context.beginPath();
      context.ellipse(c - r * 0.5, c + r * 0.3, r * 0.12, r * 0.07, 0, 0, Math.PI * 2);
      context.ellipse(c + r * 0.5, c + r * 0.3, r * 0.12, r * 0.07, 0, 0, Math.PI * 2);
      context.fill();
    }
    if (label2) {
      let px = r * 0.62;
      const font = () => popFont(px, fallbackFont);
      while (px > 8 && measure(label2, font()) > r * 1.7) px -= 1;
      context.font = font();
      context.textAlign = "center";
      context.textBaseline = "middle";
      context.fillStyle = css(2826045);
      context.fillText(label2, c, c - r * 0.08);
    }
    return canvas;
  });
  const tape = (color, pattern2) => cached(`tape:${color}:${pattern2}`, () => {
    const length = 160;
    const width = 48;
    const { canvas, context } = canvasOf3(length, width);
    const tooth = 6;
    context.beginPath();
    context.moveTo(0, 0);
    for (let y = 0; y <= width; y += tooth) context.lineTo(y % (tooth * 2) === 0 ? 0 : tooth * 0.7, y);
    context.lineTo(length, width);
    for (let y = width; y >= 0; y -= tooth) context.lineTo(y % (tooth * 2) === 0 ? length : length - tooth * 0.7, y);
    context.closePath();
    context.fillStyle = css(color, 0.78);
    context.fill();
    context.save();
    context.clip();
    if (pattern2 === "stripe") {
      context.strokeStyle = "rgba(255,255,255,0.55)";
      context.lineWidth = 7;
      for (let x = -width; x < length + width; x += 18) {
        context.beginPath();
        context.moveTo(x, width);
        context.lineTo(x + width, 0);
        context.stroke();
      }
    } else if (pattern2 === "dot") {
      context.fillStyle = "rgba(255,255,255,0.65)";
      for (let y = 8; y < width; y += 16) {
        for (let x = y / 16 % 2 === 0 ? 8 : 16; x < length; x += 16) {
          context.beginPath();
          context.arc(x, y, 3.2, 0, Math.PI * 2);
          context.fill();
        }
      }
    } else {
      context.fillStyle = "rgba(255,255,255,0.38)";
      for (let y = 0; y < width; y += 12) {
        for (let x = y / 12 % 2 === 0 ? 0 : 12; x < length; x += 24) context.fillRect(x, y, 12, 12);
      }
    }
    context.restore();
    return canvas;
  });
  const pattern = (kind) => cached(`pattern:${kind}`, () => {
    const tile = 24;
    const { canvas, context } = canvasOf3(tile, tile);
    context.fillStyle = "#ffffff";
    context.strokeStyle = "#ffffff";
    if (kind === "grid") {
      context.lineWidth = 1.2;
      context.beginPath();
      context.moveTo(0, 0.6);
      context.lineTo(tile, 0.6);
      context.moveTo(0.6, 0);
      context.lineTo(0.6, tile);
      context.stroke();
    } else if (kind === "dots") {
      context.beginPath();
      context.arc(tile / 4, tile / 4, 2.4, 0, Math.PI * 2);
      context.arc(tile * 3 / 4, tile * 3 / 4, 2.4, 0, Math.PI * 2);
      context.fill();
    } else {
      context.globalAlpha = 0.55;
      context.fillRect(0, 0, tile / 2, tile);
      context.fillRect(0, 0, tile, tile / 2);
    }
    return canvas;
  });
  const paintFilm = (color, height) => {
    const frame2 = height * 1.18;
    const width = Math.round(frame2 * 3);
    const { canvas, context } = canvasOf3(width, height);
    context.fillStyle = css(CANDY_INK, 0.92);
    context.fillRect(0, 0, width, height);
    const pitch = frame2 / 4;
    const holeW = pitch * 0.48;
    const holeH = height * 0.11;
    context.save();
    context.globalCompositeOperation = "destination-out";
    for (let k = 0; k < 12; k += 1) {
      const x = k * pitch + (pitch - holeW) / 2;
      [height * 0.07, height * 0.93 - holeH].forEach((y) => {
        context.beginPath();
        context.roundRect(x, y, holeW, holeH, holeH * 0.3);
        context.fill();
      });
    }
    context.restore();
    const base = Math.max(0, CANDY.indexOf(color));
    const colors = [color, CANDY[(base + 2) % CANDY.length], CANDY[(base + 4) % CANDY.length]];
    const icons2 = ["heart", "star", "sparkle"];
    for (let k = 0; k < 3; k += 1) {
      const x = k * frame2 + frame2 * 0.07;
      const y = height * 0.25;
      const w = frame2 * 0.86;
      const h = height * 0.5;
      context.fillStyle = css(colors[k], 0.92);
      context.beginPath();
      context.roundRect(x, y, w, h, h * 0.12);
      context.fill();
      context.fillStyle = "rgba(255,255,255,0.28)";
      context.beginPath();
      context.roundRect(x + w * 0.06, y + h * 0.1, w * 0.4, h * 0.16, h * 0.08);
      context.fill();
      context.fillStyle = "rgba(255,255,255,0.9)";
      context.save();
      context.beginPath();
      context.translate(x + w / 2, y + h / 2);
      SHAPE_PATHS[icons2[k]](context, 0, h * 0.24);
      context.fill();
      context.restore();
    }
    return canvas;
  };
  const paintCut = (color, height) => {
    const period = Math.max(10, height * 0.9);
    const { canvas, context } = canvasOf3(period, height);
    const line2 = Math.max(2, height * 0.11);
    const dash = period * 0.55;
    context.lineCap = "round";
    context.lineWidth = line2;
    context.strokeStyle = "rgba(30,16,48,0.35)";
    context.beginPath();
    context.moveTo(line2, height / 2 + line2 * 0.6);
    context.lineTo(line2 + dash - line2, height / 2 + line2 * 0.6);
    context.stroke();
    context.strokeStyle = css(color);
    context.beginPath();
    context.moveTo(line2, height / 2);
    context.lineTo(line2 + dash - line2, height / 2);
    context.stroke();
    return canvas;
  };
  const paintLace = (color, height) => {
    const scallop = Math.max(3, height * 0.21);
    const width = scallop * 4;
    const { canvas, context } = canvasOf3(width, height);
    const top = height * 0.25;
    const bottom = height * 0.75;
    const centers = [scallop, scallop * 3];
    const shape = (dy) => {
      context.beginPath();
      context.rect(0, top + dy, width, bottom - top);
      centers.forEach((cx) => {
        context.moveTo(cx + scallop, top + dy);
        context.arc(cx, top + dy, scallop, 0, Math.PI, true);
        context.moveTo(cx - scallop, bottom + dy);
        context.arc(cx, bottom + dy, scallop, Math.PI, 0, true);
      });
    };
    context.fillStyle = "rgba(30,16,48,0.22)";
    shape(height * 0.05);
    context.fill();
    context.fillStyle = "rgba(255,255,255,0.96)";
    shape(0);
    context.fill();
    context.save();
    context.globalCompositeOperation = "destination-out";
    centers.forEach((cx) => {
      [[top - scallop * 0.45, scallop * 0.3], [bottom + scallop * 0.45, scallop * 0.3], [top + height * 0.075, height * 0.035], [bottom - height * 0.075, height * 0.035]].forEach(([y, radius]) => {
        context.beginPath();
        context.arc(cx, y, Math.max(0.8, radius), 0, Math.PI * 2);
        context.fill();
      });
    });
    context.restore();
    const ribbonTop = height * 0.4;
    const ribbonHeight = height * 0.2;
    context.fillStyle = css(color);
    context.fillRect(0, ribbonTop, width, ribbonHeight);
    context.fillStyle = "rgba(255,255,255,0.45)";
    context.fillRect(0, ribbonTop + ribbonHeight * 0.18, width, Math.max(1, ribbonHeight * 0.16));
    context.fillStyle = "rgba(43,31,61,0.16)";
    context.fillRect(0, ribbonTop + ribbonHeight * 0.86, width, Math.max(1, ribbonHeight * 0.14));
    return canvas;
  };
  const strip = (style, color, thickness) => {
    const height = Math.max(10, Math.round(thickness));
    return cached(`strip:${style}:${color}:${height}`, () => style === "film" ? paintFilm(color, height) : style === "cut" ? paintCut(color, height) : paintLace(color, height));
  };
  const scissors = (thickness) => {
    const side = Math.max(20, Math.round(thickness * 2.3));
    return cached(`scissors:${side}`, () => {
      const { canvas, context } = canvasOf3(side, side);
      const c = side / 2;
      const ring = side * 0.15;
      context.lineJoin = "round";
      context.lineCap = "round";
      const outline = (path2, fill) => {
        context.beginPath();
        path2();
        context.lineWidth = side * 0.09;
        context.strokeStyle = css(CANDY_INK);
        context.stroke();
        context.fillStyle = fill;
        context.fill();
      };
      [-1, 1].forEach((dir) => outline(() => {
        context.moveTo(c - side * 0.12, c + dir * side * 0.1);
        context.quadraticCurveTo(c + side * 0.15, c - dir * side * 0.02, c + side * 0.46, c - dir * side * 0.06);
        context.quadraticCurveTo(c + side * 0.12, c + dir * side * 0.08, c - side * 0.12, c + dir * side * 0.16);
        context.closePath();
      }, "#ffffff"));
      [-1, 1].forEach((dir) => {
        context.beginPath();
        context.arc(c - side * 0.28, c + dir * side * 0.2, ring, 0, Math.PI * 2);
        context.lineWidth = side * 0.1;
        context.strokeStyle = css(CANDY_INK);
        context.stroke();
        context.lineWidth = side * 0.06;
        context.strokeStyle = css(CANDY[0]);
        context.stroke();
      });
      context.beginPath();
      context.arc(c - side * 0.06, c, side * 0.04, 0, Math.PI * 2);
      context.fillStyle = css(CANDY_INK);
      context.fill();
      return canvas;
    });
  };
  const echo = (text, color, size, axis) => {
    const px = Math.max(10, Math.round(size));
    return cached(`echo:${text}:${color}:${px}:${axis}`, () => {
      const font = popFont(px, fallbackFont);
      const textWidth = measure(text, font);
      const gapX = axis === "x" ? px * 0.6 : px * 0.2;
      const width = Math.ceil(textWidth + gapX * 2);
      const height = Math.ceil(px * (axis === "x" ? 1.25 : 1.3));
      const { canvas, context } = canvasOf3(width, height);
      context.font = font;
      context.textAlign = "center";
      context.textBaseline = "middle";
      context.lineJoin = "round";
      context.lineWidth = Math.max(1.5, px * 0.045);
      context.strokeStyle = css(color);
      context.strokeText(text, width / 2, height * 0.52);
      return canvas;
    });
  };
  const icon = (name, color, size) => {
    const node2 = resolveLucideIconNode(name) ?? resolveLucideIconNode(HANABI_FALLBACK_ICON);
    const side = Math.max(16, Math.round(size));
    return cached(`icon:${node2 ? name : "-"}:${color}:${side}`, () => {
      const { canvas, context } = canvasOf3(side, side);
      const pad = side * 0.16;
      const scale2 = (side - pad * 2) / 24;
      context.translate(pad, pad);
      context.scale(scale2, scale2);
      context.lineJoin = "round";
      context.lineCap = "round";
      const path2 = node2 ? lucideIconPath2d(node2) : null;
      const draw = (stroke, width, dx = 0, dy = 0) => {
        context.save();
        context.translate(dx, dy);
        context.strokeStyle = stroke;
        context.lineWidth = width;
        if (path2) context.stroke(path2);
        else {
          context.beginPath();
          SHAPE_PATHS.flower(context, 12, 8);
          context.stroke();
        }
        context.restore();
      };
      draw("rgba(30,16,48,0.3)", 7.2, 0.7, 1);
      draw("#ffffff", 7.2);
      draw(css(color), 2.8);
      return canvas;
    });
  };
  const sound = (text, color, size) => {
    const px = Math.max(12, Math.round(size));
    return cached(`sound:${text}:${color}:${px}`, () => {
      const font = popFont(px, fallbackFont);
      const stroke = px * 0.2;
      const shadow = px * 0.09;
      const width = Math.ceil(measure(text, font) + stroke * 2 + shadow + px * 0.2);
      const height = Math.ceil(px * 1.35 + stroke * 2 + shadow);
      const { canvas, context } = canvasOf3(width, height);
      const x = width / 2 - shadow / 2;
      const y = height / 2 - shadow / 2;
      context.font = font;
      context.textAlign = "center";
      context.textBaseline = "middle";
      context.lineJoin = "round";
      context.lineWidth = stroke * 2;
      context.strokeStyle = "rgba(43,31,61,0.9)";
      context.strokeText(text, x + shadow, y + shadow);
      context.strokeStyle = "#ffffff";
      context.strokeText(text, x, y);
      context.fillStyle = css(color);
      context.fillText(text, x, y);
      context.lineWidth = Math.max(1, px * 0.04);
      context.strokeStyle = "rgba(43,31,61,0.85)";
      context.strokeText(text, x, y);
      return canvas;
    });
  };
  const label = (text, color, size) => {
    const px = Math.max(10, Math.round(size));
    return cached(`label:${text}:${color}:${px}`, () => {
      const font = popFont(px, fallbackFont);
      const padX = px * 0.7;
      const height = Math.ceil(px * 1.7);
      const width = Math.ceil(measure(text, font) + padX * 2);
      const { canvas, context } = canvasOf3(width + 4, height + 4);
      context.fillStyle = "rgba(43,31,61,0.85)";
      context.beginPath();
      context.roundRect(3, 3, width, height, height / 2);
      context.fill();
      context.fillStyle = "#ffffff";
      context.beginPath();
      context.roundRect(0, 0, width, height, height / 2);
      context.fill();
      context.fillStyle = css(color);
      context.beginPath();
      context.roundRect(2, 2, width - 4, height - 4, (height - 4) / 2);
      context.fill();
      context.font = font;
      context.textAlign = "center";
      context.textBaseline = "middle";
      context.fillStyle = css(2826045);
      context.fillText(text, width / 2, height * 0.54);
      return canvas;
    });
  };
  return {
    sticker,
    tape,
    pattern,
    strip,
    scissors,
    echo,
    sound,
    icon,
    label,
    destroy: () => {
      cache2.forEach((texture) => texture.destroy(true));
      cache2.clear();
    }
  };
};

// folia:src/components/visualizer/hanabi/collage/collageViews.ts
var popIn = (time, at, duration = 0.32) => easeOutBack((time - at) / duration, 2.4);
var leave = (time, exitAt, exitDuration) => clamp017((time - exitAt) / Math.max(exitDuration, 0.05));
var stickerScale = (size) => size / (STICKER_PX * 0.8);
var createShotCollage = (pixi, plan, cache2, textures) => {
  const back = new pixi.Container();
  const front = new pixi.Container();
  const parts = [];
  const rect = (parent, color, alpha = 1) => {
    const sprite = new pixi.Sprite(pixi.Texture.WHITE);
    sprite.tint = color;
    sprite.alpha = alpha;
    parent.addChild(sprite);
    return sprite;
  };
  const setRect = (sprite, x, y, width, height) => {
    sprite.position.set(x, y);
    sprite.width = Math.max(0, width);
    sprite.height = Math.max(0, height);
  };
  const build = (item) => {
    switch (item.kind) {
      case "strip": {
        const holder = new pixi.Container();
        holder.position.set(item.x, item.y);
        holder.rotation = item.rotation;
        const shadow = item.style === "film" ? rect(holder, CANDY_INK, 0.3) : null;
        const band2 = new pixi.TilingSprite({
          texture: cache2.strip(item.style, item.color, item.thickness),
          width: item.length,
          height: item.thickness
        });
        holder.addChild(band2);
        const blade = item.style === "cut" ? new pixi.Sprite(cache2.scissors(item.thickness)) : null;
        if (blade) {
          blade.anchor.set(0.5);
          holder.addChild(blade);
        }
        back.addChild(holder);
        const half = item.length / 2;
        const tile = band2.texture.width || 1;
        const lift = item.thickness * 0.14;
        const wipe = item.style === "cut" ? 1.25 : item.style === "lace" ? 0.55 : 0.42;
        parts.push({
          update: (time) => {
            const raw = clamp017((time - item.at) / wipe);
            const enter = item.style === "cut" ? raw * raw * (3 - 2 * raw) : easeOutCubic3(raw);
            const exit = easeInCubic(leave(time, item.exitAt, item.exitDuration));
            holder.visible = time > item.at && exit < 1;
            if (!holder.visible) return;
            const startAt = item.from < 0 ? exit : 1 - enter;
            const endAt = item.from < 0 ? enter : 1 - exit;
            const x0 = -half + item.length * Math.min(startAt, endAt);
            const width = item.length * Math.max(0, Math.abs(endAt - startAt));
            band2.position.set(x0, -item.thickness / 2);
            band2.width = width;
            band2.height = item.thickness;
            band2.tilePosition.x = ((item.speed * time - (x0 + half)) % tile + tile) % tile;
            if (shadow) setRect(shadow, x0 + lift, -item.thickness / 2 + lift * 1.3, width, item.thickness);
            if (blade) {
              blade.visible = raw < 1 && exit <= 0;
              if (!blade.visible) return;
              const age = time - item.at;
              blade.position.set(item.from < 0 ? x0 + width : x0, 0);
              blade.scale.set(item.from < 0 ? 1 : -1, 1 - 0.3 * Math.abs(Math.sin(age * 16)));
              blade.alpha = clamp017(age / 0.12);
            }
          }
        });
        return;
      }
      case "echo": {
        const texture = cache2.echo(item.text, item.color, item.size, item.axis);
        const strip = new pixi.TilingSprite({
          texture,
          width: item.axis === "x" ? item.width : texture.width,
          height: item.axis === "x" ? texture.height : item.height
        });
        strip.anchor.set(0.5);
        strip.position.set(item.x, item.y);
        strip.rotation = item.rotation;
        back.addChild(strip);
        parts.push({
          update: (time) => {
            const enter = easeOutCubic3((time - item.at) / 0.6);
            const exit = leave(time, item.exitAt, item.exitDuration);
            const alpha = item.alpha * enter * (1 - exit);
            strip.visible = alpha > 2e-3;
            if (!strip.visible) return;
            strip.alpha = alpha;
            strip.scale.set(1 + 0.06 * (1 - enter));
            if (item.axis === "x") strip.tilePosition.x = item.speed * time;
            else strip.tilePosition.y = item.speed * time;
          }
        });
        return;
      }
      case "patch": {
        const holder = new pixi.Container();
        holder.position.set(item.x, item.y);
        const hw = item.width / 2;
        const hh = item.height / 2;
        const border = Math.max(3, Math.min(item.width, item.height) * 0.025);
        const shadow = rect(holder, CANDY_INK, item.dark ? 0.35 : 0.3);
        setRect(shadow, -hw - border + border * 2.2, -hh - border + border * 2.6, item.width + border * 2, item.height + border * 2);
        const rim = rect(holder, 16777215, item.dark ? 0.9 : 1);
        setRect(rim, -hw - border, -hh - border, item.width + border * 2, item.height + border * 2);
        const fill = rect(holder, item.color, item.dark ? 0.86 : 1);
        setRect(fill, -hw, -hh, item.width, item.height);
        if (item.pattern !== "plain") {
          const pattern = new pixi.TilingSprite({ texture: cache2.pattern(item.pattern), width: item.width, height: item.height });
          pattern.position.set(-hw, -hh);
          pattern.alpha = item.dark ? 0.16 : 0.45;
          holder.addChild(pattern);
        }
        back.addChild(holder);
        parts.push({
          update: (time) => {
            const enter = popIn(time, item.at, 0.36);
            const exit = leave(time, item.exitAt, item.exitDuration);
            holder.visible = time >= item.at && exit < 1;
            if (!holder.visible) return;
            holder.alpha = clamp017((time - item.at) / 0.12) * (1 - exit);
            holder.scale.set(1.14 - 0.14 * enter);
            holder.rotation = item.rotation + 0.12 * (1 - Math.min(1, enter));
            holder.y = item.y + exit * item.height * 0.15;
          }
        });
        return;
      }
      case "window": {
        const holder = new pixi.Container();
        holder.position.set(item.x, item.y);
        holder.rotation = item.rotation;
        const hw = item.width / 2;
        const hh = item.height / 2;
        const border = Math.max(2.5, item.bar * 0.12);
        const offset = item.bar * 0.32;
        setRect(rect(holder, CANDY[0], 0.85), -hw + offset, -hh + offset, item.width, item.height);
        setRect(rect(holder, 16777215), -hw - border, -hh - border, item.width + border * 2, item.height + border * 2);
        setRect(rect(holder, 1906744, 0.62), -hw, -hh + item.bar, item.width, item.height - item.bar);
        const titleColor = CANDY[Math.abs(Math.round(item.x + item.y)) % CANDY.length];
        setRect(rect(holder, titleColor), -hw, -hh, item.width, item.bar);
        [16748469, 16769658, 9433288].forEach((color, k) => {
          const dot = new pixi.Sprite(textures.dot);
          dot.anchor.set(0.5);
          dot.tint = color;
          dot.width = dot.height = item.bar * 0.42;
          dot.position.set(hw - item.bar * (0.55 + k * 0.6), -hh + item.bar / 2);
          holder.addChild(dot);
        });
        const title = new pixi.Sprite(cache2.label(item.title, titleColor, item.bar * 0.48));
        title.anchor.set(0, 0.5);
        title.scale.set(0.92);
        title.position.set(-hw + item.bar * 0.25, -hh + item.bar / 2);
        holder.addChild(title);
        back.addChild(holder);
        parts.push({
          update: (time) => {
            const enter = popIn(time, item.at, 0.34);
            const exit = leave(time, item.exitAt, item.exitDuration);
            holder.visible = time >= item.at && exit < 1;
            if (!holder.visible) return;
            holder.alpha = clamp017((time - item.at) / 0.1) * (1 - easeInCubic(exit));
            holder.scale.set((0.86 + 0.14 * enter) * (1 - 0.12 * exit));
          }
        });
        return;
      }
      case "sticker": {
        const sprite = new pixi.Sprite(cache2.sticker(item.shape, item.color, item.label));
        sprite.anchor.set(0.5);
        sprite.position.set(item.x, item.y);
        (item.layer === "back" ? back : front).addChild(sprite);
        const base = stickerScale(item.size);
        const phase = (item.x * 0.013 + item.y * 7e-3) % TAU2;
        parts.push({
          update: (time) => {
            const exit = leave(time, item.exitAt, Math.min(0.3, item.exitDuration));
            sprite.visible = time >= item.at && exit < 1;
            if (!sprite.visible) return;
            const enter = popIn(time, item.at);
            const age = time - item.at;
            sprite.scale.set(base * enter * (1 - easeInCubic(exit)));
            sprite.rotation = item.rotation + (1 - Math.min(1, enter)) * 0.8 + Math.sin(age * 2.6 + phase) * 0.07 + exit * 0.9;
            sprite.y = item.y + Math.sin(age * 1.9 + phase) * item.size * 0.05;
          }
        });
        return;
      }
      case "tape": {
        const sprite = new pixi.Sprite(cache2.tape(item.color, item.pattern));
        sprite.anchor.set(0.5);
        sprite.position.set(item.x, item.y);
        sprite.rotation = item.rotation;
        front.addChild(sprite);
        const sx = item.length / (sprite.texture.width || 1);
        const sy = item.width / (sprite.texture.height || 1);
        parts.push({
          update: (time) => {
            const exit = leave(time, item.exitAt, item.exitDuration);
            sprite.visible = time >= item.at && exit < 1;
            if (!sprite.visible) return;
            const stick = easeOutCubic3((time - item.at) / 0.16);
            sprite.scale.set(sx * (1.25 - 0.25 * stick), sy * (1.25 - 0.25 * stick));
            sprite.alpha = stick * (1 - exit);
          }
        });
        return;
      }
      case "label": {
        const sprite = new pixi.Sprite(cache2.label(item.text, item.color, item.size));
        sprite.anchor.set(0.5);
        sprite.position.set(item.x, item.y);
        sprite.rotation = item.rotation;
        front.addChild(sprite);
        parts.push({
          update: (time) => {
            const exit = leave(time, item.exitAt, item.exitDuration);
            sprite.visible = time >= item.at && exit < 1;
            if (!sprite.visible) return;
            sprite.scale.set(popIn(time, item.at, 0.28) * (1 - easeInCubic(exit)));
          }
        });
        return;
      }
      case "headline": {
        const sprite = new pixi.Sprite(cache2.sound(item.text, item.color, item.size));
        sprite.anchor.set(0.5);
        sprite.position.set(item.x, item.y);
        back.addChild(sprite);
        parts.push({
          update: (time) => {
            const exit = leave(time, item.exitAt, item.exitDuration);
            sprite.visible = time >= item.at && exit < 1;
            if (!sprite.visible) return;
            const age = time - item.at;
            sprite.scale.set(popIn(time, item.at, 0.4) * (1 - easeInCubic(exit)));
            sprite.rotation = item.rotation + Math.sin(age * 1.6) * 0.015;
            sprite.y = item.y + Math.sin(age * 2.1) * item.size * 0.04;
          }
        });
        return;
      }
      case "pop": {
        const sprite = new pixi.Sprite(cache2.icon(item.icon, item.color, item.size));
        sprite.anchor.set(0.5);
        sprite.position.set(item.x, item.y);
        front.addChild(sprite);
        parts.push({
          update: (time) => {
            const age = time - item.at;
            sprite.visible = age >= 0 && age <= item.duration;
            if (!sprite.visible) return;
            const fade = clamp017((age - (item.duration - 0.35)) / 0.35);
            const pop = easeOutBack(age / 0.24, 3);
            const swing = Math.exp(-age / 0.18) * Math.sin(age * 38) * 0.22;
            sprite.scale.set(Math.max(0, pop) * (1 + 0.06 * fade));
            sprite.rotation = item.rotation + swing;
            sprite.y = item.y - fade * item.size * 0.6;
            sprite.alpha = 1 - easeInCubic(fade);
          }
        });
        return;
      }
      case "whoosh": {
        const sprite = new pixi.Sprite(cache2.icon(item.icon, item.color, item.size));
        sprite.anchor.set(0.5);
        front.addChild(sprite);
        parts.push({
          update: (time) => {
            const age = time - item.at;
            const life = item.duration + 0.55;
            sprite.visible = age >= 0 && age <= life;
            if (!sprite.visible) return;
            const p = easeOutCubic3(age / item.duration);
            sprite.position.set(
              item.fromX + (item.toX - item.fromX) * p + item.size * 0.8,
              item.fromY + (item.toY - item.fromY) * p + item.size * 0.3
            );
            sprite.alpha = clamp017(age / 0.08) * (1 - clamp017((age - item.duration - 0.2) / 0.35));
            sprite.rotation = p * Math.PI * 1.5;
            sprite.scale.set(0.7 + 0.3 * clamp017(age / item.duration));
          }
        });
        return;
      }
      case "floater": {
        const sprite = new pixi.Sprite(cache2.sticker(item.shape, item.color, null));
        sprite.anchor.set(0.5);
        front.addChild(sprite);
        const base = stickerScale(item.size);
        const phase = item.x * 0.017 % TAU2;
        parts.push({
          update: (time) => {
            const age = time - item.at;
            sprite.visible = age >= 0 && age <= item.duration;
            if (!sprite.visible) return;
            const p = age / item.duration;
            sprite.position.set(item.x + Math.sin(age * 2.2 + phase) * item.sway, item.y - item.rise * p);
            sprite.rotation = Math.sin(age * 1.7 + phase) * 0.25;
            sprite.scale.set(base * Math.min(1, popIn(time, item.at, 0.3)));
            sprite.alpha = 1 - clamp017((p - 0.82) / 0.18);
          }
        });
        return;
      }
    }
  };
  plan.items.forEach(build);
  return {
    back,
    front,
    update: (time) => parts.forEach((part) => part.update(time)),
    // 纹理归缓存（场景单元销毁时一起放），这里只拆显示树。
    destroy: () => {
      back.destroy({ children: true });
      front.destroy({ children: true });
    }
  };
};

// folia:src/components/visualizer/hanabi/color.ts
var rgbOfHex = (hex) => [(hex >> 16 & 255) / 255, (hex >> 8 & 255) / 255, (hex & 255) / 255];
var hexOfRgb = (rgb) => {
  const c = (v) => Math.round(Math.min(1, Math.max(0, v)) * 255);
  return c(rgb[0]) << 16 | c(rgb[1]) << 8 | c(rgb[2]);
};
var rgbOfCss = (color) => {
  const channels = color ? parseColorChannels(color) : null;
  return channels ? [channels.r / 255, channels.g / 255, channels.b / 255] : null;
};
var hexOfCss = (color, fallback) => {
  const rgb = rgbOfCss(color);
  return rgb ? hexOfRgb(rgb) : fallback;
};
var toHsl = ([r, g, b]) => {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  const h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h / 6, s, l];
};
var toRgb = ([h, s, l]) => {
  if (s === 0) return [l, l, l];
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const channel = (t) => {
    const x = t < 0 ? t + 1 : t > 1 ? t - 1 : t;
    if (x < 1 / 6) return p + (q - p) * 6 * x;
    if (x < 1 / 2) return q;
    if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6;
    return p;
  };
  return [channel(h + 1 / 3), channel(h), channel(h - 1 / 3)];
};
var clamp018 = (value) => Math.min(1, Math.max(0, value));
var mixHue = (from, to, amount) => {
  let delta = to - from;
  if (delta > 0.5) delta -= 1;
  if (delta < -0.5) delta += 1;
  return (from + delta * amount + 1) % 1;
};
var vivid = (hex, sat, minL, maxL) => {
  const [h, s, l] = toHsl(rgbOfHex(hex));
  const saturation = s < 0.05 ? s : Math.max(s, sat);
  return hexOfRgb(toRgb([h, saturation, Math.min(maxL, Math.max(minL, l))]));
};
var linear = (v) => v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
var relativeLuminance = (hex) => {
  const [r, g, b] = rgbOfHex(hex);
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
};
var contrastRatio = (a, b) => {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
};
var DARK_INK = 2826045;
var LIGHT_INK = 16777215;
var MIN_BLOCK_CONTRAST = 3.2;
var separate = (block, ink) => {
  if (contrastRatio(block, ink) >= MIN_BLOCK_CONTRAST) return block;
  const [h, s, l] = toHsl(rgbOfHex(block));
  const darker = relativeLuminance(ink) > 0.5;
  for (let step = 1; step <= 20; step += 1) {
    const next = hexOfRgb(toRgb([h, s, clamp018(darker ? l - step * 0.04 : l + step * 0.04)]));
    if (contrastRatio(next, ink) >= MIN_BLOCK_CONTRAST) return next;
  }
  return darker ? 0 : 16777215;
};
var ensureContrast = (color, against, min) => {
  if (contrastRatio(color, against) >= min) return color;
  const [h, s, l] = toHsl(rgbOfHex(color));
  const directions = relativeLuminance(against) > 0.18 ? [-1, 1] : [1, -1];
  for (let step = 1; step <= 25; step += 1) {
    for (const direction of directions) {
      const next = hexOfRgb(toRgb([h, s, clamp018(l + direction * step * 0.04)]));
      if (contrastRatio(next, against) >= min) return next;
    }
  }
  return contrastRatio(0, against) >= contrastRatio(16777215, against) ? 0 : 16777215;
};
var MIN_SUNG_CONTRAST = 3;
var MIN_FLASH_CONTRAST = 2;
var hanabiBackdropOf = (palette) => relativeLuminance(palette.paper) > 0.5 ? 724260 : 15986665;
var resolveHanabiGlyphColors = (palette, base, under) => {
  const ink = ensureContrast(base, under, MIN_SUNG_CONTRAST);
  const candidates = [palette.accent, ...palette.sparks, palette.glow];
  const sung = candidates.find((color) => contrastRatio(color, under) >= MIN_SUNG_CONTRAST && contrastRatio(color, ink) >= 1.3) ?? ensureContrast(palette.accent, under, MIN_SUNG_CONTRAST);
  return {
    ink,
    sung,
    flash: ensureContrast(palette.glow, under, MIN_FLASH_CONTRAST),
    back: ensureContrast(palette.sparks[0] ?? palette.accent, under, MIN_FLASH_CONTRAST)
  };
};
var ROLES = {
  // 夜空：藏青、桃红、堇的色块，金、粉、水色的烟花。
  night: { blocks: [1911674, 14036852, 5979332], sparks: [16765286, 16740261, 8118258, 16777215, 12033279], accent: 16765286, glow: 16769955 },
  // 祭：朱红、瑠璃、柿色。
  festival: { blocks: [15073331, 1986722, 14239759], sparks: [16763930, 16724821, 3983615, 7208858, 16777215], accent: 16761856, glow: 16753226 },
  // 粉彩：樱粉、天蓝、柠檬。
  pastel: { blocks: [16752320, 9427199, 16773258], sparks: [16762081, 11069695, 16774576, 13942783], accent: 16744370, glow: 16773366 },
  // 黑白：纸白与灰，墨字，火花偏暖白。
  mono: { blocks: [16052714, 13222835], sparks: [16777215, 15262416, 16774102], accent: 16777215, glow: 16775142 },
  // 金：山吹金与淡金，金色的冠。
  gold: { blocks: [15904798, 16767344, 16773577], sparks: [16765806, 16756283, 16773569, 16747069], accent: 16763210, glow: 16764784 },
  // 霓虹：品红、青、紫。
  neon: { blocks: [16722902, 58879, 8006911], sparks: [16722902, 61695, 12123935, 16777215, 9399295], accent: 61695, glow: 16739312 },
  // 樱：桃红与白。
  sakura: { blocks: [16736158, 16774392, 16758994], sparks: [16758741, 16777215, 16740270, 16769260], accent: 16732051, glow: 16766696 },
  // 可爱：泡泡糖粉、天蓝、柠檬黄的色块，粉彩烟花（folia 为日系可爱 PV 加的角色）。
  kawaii: { blocks: [16744118, 8378623, 16769126], sparks: [16757721, 10547455, 16774048, 14268671, 16777215], accent: 16736162, glow: 16765416 },
  // 海：群青、碧、白。
  ocean: { blocks: [679167, 49848, 15398655], sparks: [6087167, 2883541, 16777215, 5080831], accent: 6087167, glow: 11071743 }
};
var PALETTE_ROLES = Object.keys(ROLES);
var themeColors = (theme) => {
  const primary = hexOfCss(theme.primaryColor, 16777215);
  const accent = hexOfCss(theme.accentColor, 16765286);
  const secondary = hexOfCss(theme.secondaryColor, accent);
  const spark = (hex) => vivid(hex, 0.6, 0.58, 0.8);
  return {
    blocks: [vivid(accent, 0.55, 0.3, 0.7), vivid(primary, 0.45, 0.25, 0.75), vivid(secondary, 0.5, 0.3, 0.7)],
    sparks: [spark(accent), spark(primary), spark(secondary), 16777215],
    accent: spark(accent),
    glow: vivid(accent, 0.5, 0.75, 0.88)
  };
};
var MIX_MIN_SATURATION = 0.2;
var mixColors = (role, theme) => {
  const target = toHsl(rgbOfHex(hexOfCss(theme.accentColor, role.accent)));
  if (target[1] < MIX_MIN_SATURATION) return role;
  const themed = themeColors(theme);
  const lean = (hex) => {
    const [h, s, l] = toHsl(rgbOfHex(hex));
    if (s < 0.05) return hex;
    return hexOfRgb(toRgb([mixHue(h, target[0], 0.4), s, l]));
  };
  return {
    blocks: [themed.blocks[0], ...role.blocks.slice(1).map(lean)],
    sparks: [themed.sparks[0], ...role.sparks.slice(1).map(lean)],
    accent: themed.accent,
    glow: lean(role.glow)
  };
};
var keywordColorOf = (theme) => {
  const entries = (theme.wordColors ?? []).map((entry) => ({ word: entry.word.trim().toLowerCase(), color: rgbOfCss(entry.color) })).filter((entry) => entry.word.length > 0 && entry.color !== null);
  if (entries.length === 0) return void 0;
  return (text) => {
    const key = text.trim().toLowerCase();
    if (!key) return null;
    const hit = entries.find((entry) => key === entry.word || key.includes(entry.word));
    return hit ? hexOfRgb(hit.color) : null;
  };
};
var resolveHanabiPalette = (role, theme, colorMode) => {
  const base = ROLES[role] ?? ROLES.night;
  const colors = colorMode === "theme" ? themeColors(theme) : colorMode === "mixed" ? mixColors(base, theme) : base;
  const background = hexOfCss(theme.backgroundColor, 0);
  const paper = relativeLuminance(background) > 0.4 ? DARK_INK : LIGHT_INK;
  const worst = (ink2) => Math.min(...colors.blocks.map((block) => contrastRatio(block, ink2)));
  const ink = worst(DARK_INK) >= worst(LIGHT_INK) ? DARK_INK : LIGHT_INK;
  return {
    ink,
    paper,
    blocks: colors.blocks.map((block) => separate(block, ink)),
    sparks: colors.sparks,
    accent: colors.accent,
    glow: colors.glow
  };
};

// folia:src/components/visualizer/hanabi/types.ts
var DEFAULT_HANABI_TUNING = {
  render: { scale: "global", antialias: "global" },
  colorMode: "mixed",
  sparkAmount: 1,
  ornamentAmount: 1,
  textMotion: 1,
  blockOpacity: 1,
  riseSpeed: 1,
  spin: 1,
  ambient: 1,
  glow: 1,
  bloom: 0.8,
  chorusBloom: 1.3,
  launches: true,
  overlayFrame: true,
  textOnly: false,
  sky: 0.85,
  collage: 1,
  renderQuality: "full"
};

// folia:src/components/visualizer/hanabi/hanabiTuning.ts
var MAX_BASE_RESOLUTION = 2;
var resolveHanabiBaseResolution = (devicePixelRatio) => Math.min(MAX_BASE_RESOLUTION, Math.max(1, devicePixelRatio || 1));
var HANABI_LIVE_KEYS = ["render", "sky", "overlayFrame", "bloom", "chorusBloom"];
var HANABI_OVERLAY_KEYS = ["overlayFrame", "colorMode", "textOnly"];
var requiresHanabiSceneRebuild = (previous, next) => Object.keys(next).some((key) => !HANABI_LIVE_KEYS.includes(key) && previous[key] !== next[key]);
var changedHanabiKeys = (previous, next, keys) => keys.some((key) => previous[key] !== next[key]);
var HANABI_QUALITY_PROFILES = {
  full: { glowScale: 1, ambientScale: 1 },
  balanced: { glowScale: 0.7, ambientScale: 1 },
  low: { glowScale: 0.5, ambientScale: 0.6 }
};
var resolveHanabiGlowResolution = (width, height, renderResolution, quality) => {
  const { glowScale } = HANABI_QUALITY_PROFILES[quality] ?? HANABI_QUALITY_PROFILES.full;
  if (glowScale >= 1) return renderResolution;
  return snapResolutionToTexturePool(width, height, renderResolution * glowScale);
};
var resolveHanabiGlowLevelDrop = (renderResolution, glowResolution) => glowResolution > 0 && glowResolution < renderResolution ? Math.max(0, Math.round(Math.log2(renderResolution / glowResolution))) : 0;
var resolveHanabiGlowQuality = (width, height, renderResolution, quality) => {
  const resolution = resolveHanabiGlowResolution(width, height, renderResolution, quality);
  return {
    resolution: resolution < renderResolution ? resolution : null,
    levelDrop: resolveHanabiGlowLevelDrop(renderResolution, resolution)
  };
};

// folia:src/components/visualizer/hanabi/mg/burstPlan.ts
var GOLDEN = 0.6180339887498949;
var GOLDEN_ANGLE = 2.399963229728653;
var sparkColor = (palette, colors, i) => {
  const sparks8 = palette.sparks.length > 0 ? palette.sparks : [WHITE2];
  const n = sparks8.length;
  const index = colors.length > 0 ? colors[(i % colors.length + colors.length) % colors.length] : i;
  return sparks8[(Math.round(index) % n + n) % n];
};
var planBurst = (event, palette, env) => {
  const { spec } = event;
  const kind = spec.kind;
  const rng = createRng2(`${event.seed}:${kind}`);
  const R = Math.max(4, spec.radius * env.unit * (event.scale || 1));
  const D = Math.max(0.2, spec.duration);
  const at = event.at;
  const n = Math.max(0, Math.round(spec.count * Math.max(0, env.amount)));
  const trailK = clamp017(spec.trail);
  const twinkleK = clamp017(spec.twinkle);
  const squash = event.squash ?? 1;
  const rotation = event.rotation ?? 0;
  const cosR = Math.cos(rotation);
  const sinR = Math.sin(rotation);
  const c = (i) => sparkColor(palette, spec.colors, i);
  const stars = [];
  const flashes = [];
  const minSize = Math.max(1.4, env.unit * 22e-4);
  const add = (input) => {
    const delay = input.start ?? 0;
    const life2 = Math.min(input.life, D - delay - 0.02);
    if (life2 <= 0.05) return;
    stars.push({
      x0: event.x + (input.x0 ?? 0),
      y0: event.y + (input.y0 ?? 0),
      vx: input.vx,
      vy: input.vy,
      drag: input.drag,
      fall: input.fall ?? 0,
      start: at + delay,
      life: life2,
      size: Math.max(minSize, input.size),
      color: input.color,
      endColor: input.endColor ?? input.color,
      shift: input.shift ?? 1,
      trailColor: input.trailColor ?? mixColor(input.color, EMBER, 0.3),
      trail: input.trail ?? 0,
      segments: input.trail && input.trail > 0 ? Math.max(1, input.segments ?? 3) : 0,
      fadeTail: input.fadeTail ?? 0.3,
      strobe: input.strobe ?? 0,
      strobeFrom: input.strobeFrom ?? 0,
      twinkle: input.twinkle ?? 0,
      glitter: input.glitter ?? 0,
      spiral: input.spiral ?? 0,
      spin: input.spin ?? 0,
      phase: input.phase ?? rng() * TAU2,
      depth: input.depth ?? 1,
      rank: 0,
      tex: input.tex ?? 0
    });
  };
  const flash = (x, y, delay, size, color, life2 = 0.32) => {
    if (delay >= D) return;
    flashes.push({ x: event.x + x, y: event.y + y, at: at + delay, size, color: mixColor(color, WHITE2, 0.7), life: Math.min(life2, D - delay) });
  };
  const tiltA = rng() * TAU2;
  const tiltCos = Math.cos(tiltA);
  const tiltSin = Math.sin(tiltA);
  const sphere = (i, count, jitter = 0.25) => {
    const z = 1 - 2 * (i + 0.5) / count;
    const r = Math.sqrt(Math.max(0, 1 - z * z));
    const phi = i * GOLDEN_ANGLE + (rng() - 0.5) * jitter;
    const x = r * Math.cos(phi);
    const y0 = r * Math.sin(phi);
    return [x, y0 * tiltCos - z * tiltSin, y0 * tiltSin + z * tiltCos];
  };
  const planar = (x, y) => {
    const sy = y * squash;
    return [x * cosR - sy * sinR, x * sinR + sy * cosR];
  };
  const depthOf = (z) => 0.62 + 0.38 * (z + 1) / 2;
  const life = (low, high) => D * lerp3(low, high, rng());
  const c0 = c(0);
  const c1 = c(1);
  const c2 = c(2);
  switch (kind) {
    case "kiku": {
      const core = Math.round(n * 0.2);
      const main = n - core;
      const k = 3.2;
      for (let i = 0; i < main; i += 1) {
        const [dx, dy, dz] = sphere(i, main);
        const speed = R * k * (0.94 + rng() * 0.12);
        add({
          vx: dx * speed,
          vy: dy * speed,
          drag: k,
          fall: R * 0.3,
          life: life(0.78, 0.98),
          size: R * 0.02,
          color: c0,
          endColor: mixColor(c0, WHITE2, 0.65),
          shift: 0.7,
          trail: 0.1 + trailK * 0.38,
          segments: 3,
          trailColor: mixColor(c0, EMBER, 0.3),
          twinkle: twinkleK,
          depth: depthOf(dz)
        });
      }
      for (let i = 0; i < core; i += 1) {
        const [dx, dy, dz] = sphere(i, core);
        const speed = R * 3.6 * 0.42 * (0.95 + rng() * 0.1);
        add({
          vx: dx * speed,
          vy: dy * speed,
          drag: 3.6,
          fall: R * 0.2,
          life: life(0.4, 0.55),
          size: R * 0.017,
          color: c1,
          trail: 0.04 + trailK * 0.08,
          segments: 1,
          fadeTail: 0.2,
          depth: depthOf(dz)
        });
      }
      flash(0, 0, 0, R * 1.1, c0, 0.36);
      break;
    }
    case "botan": {
      const core = Math.round(n * 0.22);
      const main = n - core;
      const k = 3.6;
      for (let i = 0; i < main; i += 1) {
        const [dx, dy, dz] = sphere(i, main, 0.12);
        const speed = R * k * (0.97 + rng() * 0.06);
        add({
          vx: dx * speed,
          vy: dy * speed,
          drag: k,
          fall: R * 0.24,
          life: life(0.85, 0.97),
          size: R * 0.034,
          color: c0,
          endColor: c1,
          shift: 0.48,
          fadeTail: 0.12,
          twinkle: twinkleK * 0.6,
          depth: depthOf(dz)
        });
      }
      for (let i = 0; i < core; i += 1) {
        const [dx, dy, dz] = sphere(i, core, 0.12);
        const speed = R * k * 0.5;
        add({
          vx: dx * speed,
          vy: dy * speed,
          drag: k,
          fall: R * 0.2,
          life: life(0.6, 0.72),
          size: R * 0.03,
          color: c2,
          endColor: mixColor(c2, WHITE2, 0.5),
          shift: 0.55,
          fadeTail: 0.12,
          depth: depthOf(dz)
        });
      }
      flash(0, 0, 0, R * 1.2, c0, 0.3);
      break;
    }
    case "yanagi": {
      const k = 2.5;
      const gold = mixColor(c0, GOLD, 0.6);
      for (let i = 0; i < n; i += 1) {
        const [dx, dy, dz] = sphere(i, n, 0.4);
        const speed = R * k * 0.72 * (0.9 + rng() * 0.2);
        add({
          vx: dx * speed,
          vy: dy * speed - R * 0.25,
          drag: k,
          fall: R * 0.95,
          life: life(0.88, 0.99),
          size: R * 0.013,
          color: gold,
          endColor: mixColor(gold, EMBER, 0.6),
          shift: 0.6,
          trail: 0.35 + trailK * 0.95,
          segments: 4,
          trailColor: mixColor(gold, EMBER, 0.35),
          fadeTail: 0.45,
          glitter: 0.25 + twinkleK * 0.5,
          depth: depthOf(dz) * 0.9
        });
      }
      flash(0, 0, 0, R * 0.8, gold, 0.3);
      break;
    }
    case "kamuro": {
      const k = 3;
      const gold = mixColor(c0, GOLD, 0.78);
      for (let i = 0; i < n; i += 1) {
        const [dx, dy, dz] = sphere(i, n, 0.2);
        const speed = R * k * 1.05 * (0.95 + rng() * 0.1);
        add({
          vx: dx * speed,
          vy: dy * speed - R * 0.12,
          drag: k,
          fall: R * 0.55,
          life: life(0.9, 0.99),
          size: R * 0.017,
          color: gold,
          endColor: mixColor(gold, EMBER, 0.5),
          shift: 0.55,
          trail: 0.45 + trailK * 0.8,
          segments: 4,
          trailColor: mixColor(gold, EMBER, 0.25),
          fadeTail: 0.5,
          glitter: 0.55 + twinkleK * 0.45,
          depth: depthOf(dz)
        });
      }
      flash(0, 0, 0, R * 1.3, gold, 0.42);
      break;
    }
    case "senrin": {
      const flowers = Math.max(4, Math.min(10, Math.round(n / 14)));
      const per = Math.max(6, Math.round(n / flowers));
      const k = 4.4;
      for (let f = 0; f < flowers; f += 1) {
        const angle = f * GOLDEN_ANGLE + rng() * 0.6;
        const dist = R * 0.78 * Math.sqrt((f + 0.5) / flowers);
        const ox = Math.cos(angle) * dist;
        const oy = Math.sin(angle) * dist;
        const delay = 0.06 + f / flowers * D * 0.42 + rng() * 0.05;
        const r = R * (0.2 + rng() * 0.08);
        const color = c(f);
        for (let i = 0; i < per; i += 1) {
          const [dx, dy, dz] = sphere(i, per, 0.3);
          const speed = r * k * (0.92 + rng() * 0.16);
          add({
            x0: ox,
            y0: oy,
            start: delay,
            vx: dx * speed,
            vy: dy * speed,
            drag: k,
            fall: R * 0.16,
            life: D * (0.32 + rng() * 0.12),
            size: R * 0.017,
            color,
            endColor: mixColor(color, WHITE2, 0.6),
            shift: 0.65,
            trail: trailK * 0.08,
            segments: 1,
            fadeTail: 0.25,
            twinkle: 0.3 + twinkleK * 0.7,
            depth: depthOf(dz)
          });
        }
        flash(ox, oy, delay, r * 1.4, color, 0.22);
      }
      break;
    }
    case "ring": {
      const k = 3.4;
      const outer = Math.round(n * 0.7);
      const inner = Math.round(n * 0.2);
      const core = n - outer - inner;
      const ringOf = (count, reach, color, size, lifeLow) => {
        for (let i = 0; i < count; i += 1) {
          const [dx, dy] = planar(Math.cos(TAU2 * i / count), Math.sin(TAU2 * i / count));
          const speed = R * k * reach * (0.99 + rng() * 0.02);
          add({
            vx: dx * speed,
            vy: dy * speed,
            drag: k,
            fall: R * 0.18,
            life: life(lifeLow, lifeLow + 0.12),
            size,
            color,
            endColor: mixColor(color, WHITE2, 0.5),
            shift: 0.75,
            trail: 0.05 + trailK * 0.2,
            segments: 2,
            twinkle: twinkleK
          });
        }
      };
      ringOf(outer, 1, c0, R * 0.022, 0.85);
      ringOf(inner, 0.58, c1, R * 0.018, 0.7);
      for (let i = 0; i < core; i += 1) {
        const [dx, dy, dz] = sphere(i, Math.max(1, core));
        const speed = R * k * 0.18;
        add({ vx: dx * speed, vy: dy * speed, drag: k, fall: R * 0.15, life: life(0.45, 0.6), size: R * 0.02, color: c2, depth: depthOf(dz) });
      }
      flash(0, 0, 0, R * 0.9, c0, 0.3);
      break;
    }
    case "heart":
    case "star": {
      const k = 3.4;
      const outline = Math.max(12, Math.round(n * 0.88));
      for (let i = 0; i < outline; i += 1) {
        const u = i / outline;
        let x;
        let y;
        if (kind === "heart") {
          const t = u * TAU2;
          x = 16 * Math.sin(t) ** 3 / 17;
          y = -(13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t)) / 17;
        } else {
          const edge = u * 10;
          const e = Math.floor(edge);
          const f = edge - e;
          const vertex2 = (index) => {
            const radius = index % 2 === 0 ? 1 : 0.4;
            const a = -Math.PI / 2 + index * Math.PI / 5;
            return [Math.cos(a) * radius, Math.sin(a) * radius];
          };
          const [ax, ay] = vertex2(e);
          const [bx, by] = vertex2(e + 1);
          x = lerp3(ax, bx, f);
          y = lerp3(ay, by, f);
        }
        const [dx, dy] = planar(x, y);
        const speed = R * k * (0.99 + rng() * 0.02);
        add({
          vx: dx * speed,
          vy: dy * speed,
          drag: k,
          fall: R * 0.1,
          life: life(0.8, 0.92),
          size: R * 0.024,
          color: c0,
          endColor: mixColor(c0, WHITE2, 0.55),
          shift: 0.7,
          trail: 0.04 + trailK * 0.1,
          segments: 1,
          fadeTail: 0.25,
          twinkle: twinkleK
        });
      }
      const core = n - outline;
      for (let i = 0; i < core; i += 1) {
        const [dx, dy, dz] = sphere(i, Math.max(1, core));
        const speed = R * k * 0.15;
        add({ vx: dx * speed, vy: dy * speed, drag: k, fall: R * 0.1, life: life(0.4, 0.55), size: R * 0.018, color: c1, depth: depthOf(dz) });
      }
      flash(0, 0, 0, R * 0.8, c0, 0.28);
      break;
    }
    case "palm": {
      const branches = Math.max(6, Math.min(14, Math.round(n / 9)));
      const crumbs = Math.max(0, Math.min(6, Math.floor((n - branches) / branches)));
      const k = 2.3;
      const gold = mixColor(c0, GOLD, 0.45);
      for (let b = 0; b < branches; b += 1) {
        const angle = TAU2 * b / branches + (rng() - 0.5) * 0.35;
        const up = -Math.sin(angle);
        const reach = 1 + up * 0.15 + (rng() - 0.5) * 0.1;
        const dx = Math.cos(angle);
        const dy = Math.sin(angle);
        const speed = R * k * reach;
        add({
          vx: dx * speed,
          vy: dy * speed,
          drag: k,
          fall: R * 0.7,
          life: life(0.88, 0.98),
          size: R * 0.05,
          color: gold,
          endColor: mixColor(gold, EMBER, 0.55),
          shift: 0.55,
          trail: 0.4 + trailK * 0.55,
          segments: 5,
          trailColor: mixColor(gold, EMBER, 0.3),
          fadeTail: 0.4,
          glitter: 0.3 + twinkleK * 0.4
        });
        for (let j = 0; j < crumbs; j += 1) {
          const f = 0.9 - j * 0.1;
          add({
            vx: dx * speed * f + (rng() - 0.5) * R * 0.3,
            vy: dy * speed * f + (rng() - 0.5) * R * 0.3,
            drag: k,
            fall: R * 0.75,
            life: life(0.55, 0.85),
            size: R * 0.014,
            color: mixColor(gold, WHITE2, 0.3),
            trail: 0.08,
            segments: 1,
            fadeTail: 0.5,
            glitter: 0.8
          });
        }
      }
      flash(0, 0, 0, R * 1, gold, 0.4);
      break;
    }
    case "crossette": {
      const parents = Math.max(6, Math.min(16, Math.round(n / 5)));
      const k = 2.8;
      const kc = 3.4;
      const fall = R * 0.32;
      for (let p = 0; p < parents; p += 1) {
        const angle = TAU2 * p / parents + (rng() - 0.5) * 0.4;
        const speed = R * k * 0.72 * (0.9 + rng() * 0.2);
        const vx = Math.cos(angle) * speed;
        const vy = Math.sin(angle) * speed;
        const split = D * (0.28 + rng() * 0.08);
        add({
          vx,
          vy,
          drag: k,
          fall,
          life: split,
          size: R * 0.024,
          color: c0,
          trail: 0.08 + trailK * 0.2,
          segments: 2,
          fadeTail: 0.05
        });
        const e = Math.exp(-k * split);
        const f = (1 - e) / k;
        const sx = vx * f;
        const sy = vy * f + fall * (split - f);
        const svx = vx * e;
        const svy = (vy - fall) * e + fall;
        const turn = angle + Math.PI / 4 + (rng() - 0.5) * 0.3;
        for (let q = 0; q < 4; q += 1) {
          const a = turn + q * Math.PI / 2;
          const cs = R * kc * 0.36;
          add({
            x0: sx,
            y0: sy,
            start: split,
            vx: svx * 0.35 + Math.cos(a) * cs,
            vy: svy * 0.35 + Math.sin(a) * cs,
            drag: kc,
            fall: R * 0.38,
            life: D * (0.45 + rng() * 0.12),
            size: R * 0.018,
            color: c1,
            endColor: mixColor(c1, WHITE2, 0.5),
            shift: 0.7,
            trail: 0.06 + trailK * 0.18,
            segments: 2,
            twinkle: twinkleK
          });
        }
        flash(sx, sy, split, R * 0.2, c1, 0.16);
      }
      flash(0, 0, 0, R * 0.8, c0, 0.3);
      break;
    }
    case "strobe": {
      const k = 4;
      const white = mixColor(c0, WHITE2, 0.55);
      for (let i = 0; i < n; i += 1) {
        const [dx, dy, dz] = sphere(i, n, 0.6);
        const speed = R * k * 0.88 * (0.8 + rng() * 0.3);
        add({
          vx: dx * speed,
          vy: dy * speed,
          drag: k,
          fall: R * 0.12,
          life: life(0.85, 0.99),
          size: R * 0.028,
          color: white,
          endColor: c(i),
          shift: 0.25,
          strobe: 7 + rng() * 7,
          strobeFrom: 0.3 + rng() * 0.25,
          fadeTail: 0.15,
          depth: depthOf(dz),
          tex: rng() < 0.3 ? 1 : 0
        });
      }
      flash(0, 0, 0, R * 0.9, white, 0.3);
      break;
    }
    case "hachi": {
      const k = 2.5;
      const silver = mixColor(c0, WHITE2, 0.7);
      for (let i = 0; i < n; i += 1) {
        const angle = rng() * TAU2;
        const speed = R * k * (0.3 + rng() * 0.6);
        add({
          vx: Math.cos(angle) * speed,
          vy: Math.sin(angle) * speed,
          drag: k,
          fall: R * 0.25,
          life: life(0.5, 0.98),
          size: R * 0.013,
          color: silver,
          endColor: c(i),
          shift: 0.6,
          trail: 0.08 + trailK * 0.14,
          segments: 2,
          trailColor: mixColor(silver, EMBER, 0.3),
          spiral: R * (0.05 + rng() * 0.11),
          spin: (rng() < 0.5 ? -1 : 1) * (9 + rng() * 12),
          twinkle: 0.4 + twinkleK * 0.6,
          fadeTail: 0.3
        });
      }
      flash(0, 0, 0, R * 0.6, silver, 0.24);
      break;
    }
    case "willow-ring": {
      const inner = Math.round(n * 0.35);
      const outer = n - inner;
      const gold = mixColor(c1, GOLD, 0.7);
      for (let i = 0; i < inner; i += 1) {
        const [dx, dy] = planar(Math.cos(TAU2 * i / inner), Math.sin(TAU2 * i / inner));
        const speed = R * 3.6 * 0.46;
        add({
          vx: dx * speed,
          vy: dy * speed,
          drag: 3.6,
          fall: R * 0.15,
          life: life(0.45, 0.55),
          size: R * 0.03,
          color: c0,
          endColor: mixColor(c0, WHITE2, 0.5),
          shift: 0.6,
          fadeTail: 0.1
        });
      }
      for (let i = 0; i < outer; i += 1) {
        const [dx, dy, dz] = sphere(i, outer, 0.4);
        const speed = R * 2.6 * (0.92 + rng() * 0.12);
        add({
          vx: dx * speed,
          vy: dy * speed - R * 0.2,
          drag: 2.6,
          fall: R * 0.9,
          life: life(0.88, 0.99),
          size: R * 0.013,
          color: gold,
          endColor: mixColor(gold, EMBER, 0.6),
          shift: 0.6,
          trail: 0.35 + trailK * 0.9,
          segments: 4,
          trailColor: mixColor(gold, EMBER, 0.3),
          fadeTail: 0.45,
          glitter: 0.3 + twinkleK * 0.4,
          depth: depthOf(dz) * 0.9
        });
      }
      flash(0, 0, 0, R * 1, c0, 0.34);
      break;
    }
    case "mine": {
      const volleys = Math.max(4, Math.min(8, Math.round(D * 2.6)));
      const per = Math.max(4, Math.round(n / volleys));
      const k = 1.7;
      for (let v = 0; v < volleys; v += 1) {
        const delay = v / volleys * D * 0.55;
        const lean = (v % 2 === 0 ? -1 : 1) * (0.12 + rng() * 0.2);
        const color = c(v);
        const lifeV = Math.min(0.9 + rng() * 0.5, D * 0.6);
        for (let i = 0; i < per; i += 1) {
          const angle = -Math.PI / 2 + lean + ((i + 0.5) / per - 0.5) * 1.3 + (rng() - 0.5) * 0.12;
          const speed = R * k * (1.45 + rng() * 0.45);
          add({
            start: delay,
            vx: Math.cos(angle) * speed,
            vy: Math.sin(angle) * speed,
            drag: k,
            fall: R * 0.9,
            life: lifeV * (0.8 + rng() * 0.2),
            size: R * 0.02,
            color,
            endColor: mixColor(color, WHITE2, 0.6),
            shift: 0.7,
            trail: 0.1 + trailK * 0.3,
            segments: 3,
            fadeTail: 0.3,
            twinkle: twinkleK
          });
        }
        flash(0, 0, delay, R * 0.35, color, 0.18);
      }
      break;
    }
    default: {
      const never = kind;
      return never;
    }
  }
  for (let i = 0; i < stars.length; i += 1) stars[i].rank = (i + 1) * GOLDEN % 1;
  let end = at;
  for (const star of stars) end = Math.max(end, star.start + star.life);
  for (const item of flashes) end = Math.max(end, item.at + item.life);
  return { at, end, stars, flashes };
};
var starPosition = (star, tau, out) => {
  const t = tau < 0 ? 0 : tau;
  const e = Math.exp(-star.drag * t);
  const f = (1 - e) / star.drag;
  let x = star.x0 + star.vx * f;
  let y = star.y0 + star.vy * f + star.fall * (t - f);
  if (star.spiral > 0) {
    const r = star.spiral * (1 - Math.exp(-3 * t));
    const a = star.phase + star.spin * t;
    x += r * Math.cos(a);
    y += r * Math.sin(a);
  }
  out.x = x;
  out.y = y;
  return out;
};
var starBase = (star, tau) => {
  if (tau < 0 || tau > star.life) return 0;
  const u = tau / star.life;
  let b = star.depth * clamp017(tau / 0.035);
  if (u > 1 - star.fadeTail) {
    const k = (1 - u) / star.fadeTail;
    b *= k * k * (3 - 2 * k);
  }
  return b;
};
var starBrightness = (star, tau) => {
  let b = starBase(star, tau);
  if (b <= 0) return 0;
  if (star.strobe > 0 && tau > star.strobeFrom) {
    const on = (tau * star.strobe + star.phase) % 1 < 0.42;
    b *= on ? 1 : 0.05;
  }
  const u = tau / star.life;
  if (star.twinkle > 0 && u > 0.5) {
    const n = hash01(Math.floor(tau * 24), star.phase * 97);
    b *= 1 - star.twinkle * clamp017((u - 0.5) / 0.2) * (n < 0.45 ? 0.85 : 0);
  }
  return b;
};
var starColor = (star, tau) => {
  const u = tau / star.life;
  let color = star.shift < 1 ? mixColor(star.color, star.endColor, (u - star.shift) / 0.1) : star.color;
  if (star.glitter > 0 && hash01(Math.floor(tau * 30), star.phase * 53) < star.glitter * 0.35) color = mixColor(color, WHITE2, 0.75);
  return color;
};
var starSize = (star, tau) => {
  const u = clamp017(tau / star.life);
  let size = star.size * (1 - 0.45 * u);
  if (star.glitter > 0 && hash01(Math.floor(tau * 30), star.phase * 53) < star.glitter * 0.35) size *= 1.6;
  return size;
};
var burstActive = (plan, time) => time >= plan.at && time <= plan.end;
var scratchA = { x: 0, y: 0 };
var scratchB = { x: 0, y: 0 };
var emitSegment = (emit, a, b, thickness, alpha, tint) => {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  const length = Math.hypot(dx, dy);
  if (length < 0.6 || alpha < 0.01) return true;
  const rotation = Math.atan2(dy, dx) + Math.PI / 2;
  return emit("streak", (a.x + b.x) / 2, (a.y + b.y) / 2, thickness, length + thickness * 0.5, rotation, alpha, tint);
};
var burstDemand = (plans, time) => {
  let stars = 0;
  let flashes = 0;
  for (const plan of plans) {
    if (!burstActive(plan, time)) continue;
    for (const item of plan.flashes) if (time >= item.at && time < item.at + item.life) flashes += 2;
    for (const star of plan.stars) {
      const tau = time - star.start;
      if (tau >= 0 && tau <= star.life) stars += 1 + star.segments;
    }
  }
  return { stars, flashes };
};
var drawBursts = (plans, time, budget, emit) => {
  const demand = burstDemand(plans, time);
  if (demand.stars + demand.flashes === 0 || budget <= 0) return 0;
  const keep = demand.stars + demand.flashes <= budget ? 2 : Math.max(0, (budget - demand.flashes) * 0.97) / Math.max(1, demand.stars);
  let used = 0;
  const put = (texture, x, y, w, h, r, a, tint) => {
    if (used >= budget) return false;
    if (!emit(texture, x, y, w, h, r, a, tint)) return false;
    used += 1;
    return true;
  };
  for (const plan of plans) {
    if (!burstActive(plan, time)) continue;
    for (const item of plan.flashes) {
      const age = time - item.at;
      if (age < 0 || age >= item.life) continue;
      const k = age / item.life;
      const alpha = clamp017(age / 0.02) * (1 - k) ** 2;
      const halo = item.size * (0.55 + 0.6 * Math.sqrt(k));
      if (!put("flash", item.x, item.y, halo, halo, 0, alpha * 0.55, item.color)) return used;
      const core = item.size * 0.35 * (1 - k * 0.6);
      if (!put("flash", item.x, item.y, core, core, 0, alpha, WHITE2)) return used;
    }
  }
  for (const plan of plans) {
    if (!burstActive(plan, time)) continue;
    for (const star of plan.stars) {
      const tau = time - star.start;
      if (tau < 0 || tau > star.life || star.rank >= keep) continue;
      const base = starBase(star, tau);
      if (base <= 0) continue;
      const head = starPosition(star, tau, scratchA);
      const hx = head.x;
      const hy = head.y;
      const size = starSize(star, tau);
      if (star.segments > 0) {
        const step = star.trail / star.segments;
        let prevX = hx;
        let prevY = hy;
        for (let j = 1; j <= star.segments; j += 1) {
          const back = Math.max(0, tau - step * j);
          const old = starPosition(star, back, scratchB);
          const fade = (1 - (j - 1) / star.segments) ** 1.3;
          const thickness = Math.max(1.2, size * 0.75 * (1 - 0.45 * (j / star.segments)));
          scratchA.x = prevX;
          scratchA.y = prevY;
          if (!emitSegment(put, scratchA, old, thickness, base * fade * 0.95, star.trailColor)) return used;
          prevX = old.x;
          prevY = old.y;
          if (back <= 0) break;
        }
      }
      const alpha = starBrightness(star, tau);
      if (alpha < 0.01) continue;
      const tint = starColor(star, tau);
      const drawn = star.tex === 1 ? size * 3.4 : size * 3.4;
      if (!put(star.tex === 1 ? "star4" : "glow", hx, hy, drawn, drawn, star.phase, alpha, tint)) return used;
    }
  }
  return used;
};
var LAUNCH_EMBER_LIFE = 0.6;
var LAUNCH_EMBER_STEP = 0.032;
var LAUNCH_TRAIL_SEGMENTS = 5;
var launchEnd = (launch2) => launch2.at + launch2.duration + LAUNCH_EMBER_LIFE;
var launchHead = (launch2, p, salt, out) => {
  const k = clamp017(p);
  const rise = 1 - (1 - k) ** 2;
  const span = Math.hypot(launch2.toX - launch2.fromX, launch2.toY - launch2.fromY);
  const freq = 2.2 + hash01(1, salt) * 1.6;
  const phase = hash01(2, salt) * TAU2;
  const sway = Math.sin(k * freq * TAU2 + phase) * span * 0.018 * (1 - k * 0.7);
  out.x = lerp3(launch2.fromX, launch2.toX, rise) + sway;
  out.y = lerp3(launch2.fromY, launch2.toY, rise);
  return out;
};
var drawLaunch = (launch2, time, unit, emit) => {
  const age = time - launch2.at;
  if (age < 0 || time > launchEnd(launch2)) return true;
  const salt = hashString(launch2.seed) % 1e5;
  const duration = Math.max(0.05, launch2.duration);
  const color = launch2.color;
  const ember = mixColor(color, GOLD, 0.55);
  const size = unit * 9e-3;
  const firstJ = Math.max(0, Math.ceil((age - LAUNCH_EMBER_LIFE) / LAUNCH_EMBER_STEP));
  const lastJ = Math.floor(Math.min(age, duration) / LAUNCH_EMBER_STEP);
  for (let j = firstJ; j <= lastJ; j += 1) {
    const born = j * LAUNCH_EMBER_STEP;
    const tau = age - born;
    if (tau < 0 || tau > LAUNCH_EMBER_LIFE) continue;
    const from = launchHead(launch2, born / duration, salt, scratchB);
    const vx = (hash01(j * 3 + 1, salt) - 0.5) * unit * 0.12;
    const vy = (hash01(j * 3 + 2, salt) - 0.2) * unit * 0.05;
    const drag = 2.4;
    const fall = unit * 0.09;
    const e = Math.exp(-drag * tau);
    const f = (1 - e) / drag;
    const x = from.x + vx * f;
    const y = from.y + vy * f + fall * (tau - f);
    const k = tau / LAUNCH_EMBER_LIFE;
    const flicker = hash01(j * 7 + Math.floor(tau * 20), salt) < 0.3 ? 0.4 : 1;
    const alpha = (1 - k) ** 1.5 * flicker * 0.85;
    const s = size * (0.35 + hash01(j * 5, salt) * 0.35) * (1 - k * 0.5);
    if (!emit("glow", x, y, s * 2.6, s * 2.6, 0, alpha, ember)) return false;
  }
  if (age > duration) return true;
  const p = age / duration;
  const head = launchHead(launch2, p, salt, scratchA);
  const hx = head.x;
  const hy = head.y;
  let prevX = hx;
  let prevY = hy;
  for (let j = 1; j <= LAUNCH_TRAIL_SEGMENTS; j += 1) {
    const old = launchHead(launch2, Math.max(0, p - 0.07 * j / duration), salt, scratchB);
    const fade = 1 - (j - 1) / LAUNCH_TRAIL_SEGMENTS;
    scratchA.x = prevX;
    scratchA.y = prevY;
    if (!emitSegment(emit, scratchA, old, Math.max(1, size * 0.9 * fade), 0.8 * fade, mixColor(color, EMBER, 0.3))) return false;
    prevX = old.x;
    prevY = old.y;
  }
  const pulse = 0.85 + 0.15 * Math.sin(age * 40 + salt);
  const dim = 1 - 0.35 * clamp017((p - 0.8) / 0.2);
  if (!emit("glow", hx, hy, size * 4.2 * pulse, size * 4.2 * pulse, 0, 0.9 * dim, color)) return false;
  return emit("dot", hx, hy, size * 0.9, size * 0.9, 0, dim, mixColor(color, WHITE2, 0.8));
};
var launchDemand = (launch2, time) => {
  const age = time - launch2.at;
  if (age < 0 || time > launchEnd(launch2)) return 0;
  const embers = Math.floor(Math.min(age, LAUNCH_EMBER_LIFE) / LAUNCH_EMBER_STEP) + 1;
  return embers + (age <= launch2.duration ? LAUNCH_TRAIL_SEGMENTS + 2 : 0);
};

// folia:src/components/visualizer/hanabi/mg/fireworks.ts
var PLAN_CACHE_LIMIT = 160;
var createFireworks = (pixi, textures, options) => {
  const view = new pixi.Container({ isRenderGroup: true });
  const unit = Math.min(options.width, options.height);
  const maxParticles = Math.max(0, Math.floor(options.maxParticles));
  const poolOf = (blendMode) => {
    const layer = new pixi.Container();
    layer.blendMode = blendMode;
    view.addChild(layer);
    return { layer, sprites: [], used: 0, shown: 0 };
  };
  const normal = poolOf("normal");
  const additive = poolOf("add");
  let used = 0;
  const plans = /* @__PURE__ */ new Map();
  const active = [];
  const textureOf = {
    glow: textures.glow,
    dot: textures.dot,
    star4: textures.star4,
    streak: textures.streak,
    flash: textures.glow
  };
  const emit = (texture, x, y, width, height, rotation, alpha, tint) => {
    if (used >= maxParticles) return false;
    const pool = texture === "flash" ? additive : normal;
    let sprite = pool.sprites[pool.used];
    if (!sprite) {
      sprite = new pixi.Sprite(textures.glow);
      sprite.anchor.set(0.5);
      pool.layer.addChild(sprite);
      pool.sprites.push(sprite);
    }
    pool.used += 1;
    sprite.texture = textureOf[texture];
    sprite.visible = true;
    sprite.position.set(x, y);
    sprite.rotation = rotation;
    sprite.width = width;
    sprite.height = height;
    sprite.alpha = alpha > 1 ? 1 : alpha;
    sprite.tint = tint;
    used += 1;
    return true;
  };
  const planOf = (event) => {
    let plan = plans.get(event);
    if (!plan) {
      plan = planBurst(event, options.palette, { unit, amount: options.amount });
      plans.set(event, plan);
    }
    return plan;
  };
  const hideRest = (pool) => {
    for (let i = pool.used; i < pool.shown; i += 1) pool.sprites[i].visible = false;
    pool.shown = pool.used;
    pool.used = 0;
  };
  const update = (time, bursts, launches) => {
    used = 0;
    active.length = 0;
    for (const event of bursts) {
      if (time < event.at || time > event.at + event.spec.duration) continue;
      const plan = planOf(event);
      if (burstActive(plan, time)) active.push(plan);
    }
    if (plans.size > PLAN_CACHE_LIMIT) {
      const keep = new Set(active);
      for (const [event, plan] of plans) if (!keep.has(plan)) plans.delete(event);
    }
    let launchBudget = 0;
    for (const launch2 of launches) {
      if (time < launch2.at || time > launchEnd(launch2)) continue;
      launchBudget += launchDemand(launch2, time);
    }
    launchBudget = Math.min(launchBudget, Math.floor(maxParticles * 0.2));
    for (const launch2 of launches) {
      if (used >= launchBudget) break;
      if (!drawLaunch(launch2, time, unit, emit)) break;
    }
    drawBursts(active, time, maxParticles - used, emit);
    hideRest(normal);
    hideRest(additive);
    view.visible = used > 0;
  };
  return {
    view,
    update,
    destroy: () => {
      plans.clear();
      view.destroy({ children: true });
    }
  };
};

// folia:src/components/visualizer/hanabi/mg/glow.ts
var BASE = {
  strength: 1.1,
  threshold: 0.2,
  knee: 0.25,
  levels: 5,
  spread: 0.85,
  tint: [1, 0.96, 0.9]
};
var createHanabiGlow = (pixi, amount, quality = { resolution: null, levelDrop: 0 }, padding = 48) => {
  const filter = createBloomFilter(pixi, {
    ...BASE,
    strength: BASE.strength * Math.max(0, amount),
    levels: Math.max(1, BASE.levels - quality.levelDrop),
    padding
  });
  filter.resolution = quality.resolution ?? "inherit";
  return filter;
};

// folia:src/components/visualizer/hanabi/text/animations.ts
var ENTER_DURATION = {
  pop: 0.45,
  drop: 0.62,
  rise: 0.6,
  spin: 0.62,
  wipe: 0.42,
  type: 0.12,
  scramble: 0.75,
  stretch: 0.55,
  elastic: 0.85,
  split: 0.5,
  spiral: 0.85,
  flip: 0.55,
  glitch: 0.6,
  stamp: 0.5,
  wave: 0.75,
  zoom: 0.6,
  burst: 0.75
};
var ENTER_ARRIVAL = {
  pop: 0,
  drop: 0.4,
  rise: 0.3,
  spin: 0.2,
  wipe: 0,
  type: 0,
  scramble: 0,
  stretch: 0.1,
  elastic: 0.1,
  split: 0.3,
  spiral: 0.45,
  flip: 0.15,
  glitch: 0,
  stamp: 0.35,
  wave: 0.3,
  zoom: 0.25,
  burst: 0.3
};
var STAMP_IMPACT = 0.5;
var clamp019 = (value) => value <= 0 ? 0 : value >= 1 ? 1 : value;
var easeOutCubic4 = (t) => 1 - (1 - t) ** 3;
var easeInCubic2 = (t) => t * t * t;
var easeInQuad = (t) => t * t;
var easeOutQuad = (t) => 1 - (1 - t) * (1 - t);
var easeOutExpo3 = (t) => t >= 1 ? 1 : 1 - 2 ** (-10 * t);
var easeOutBack2 = (t, s = 1.70158) => 1 + (s + 1) * (t - 1) ** 3 + s * (t - 1) ** 2;
var easeInBack2 = (t, s = 1.70158) => (s + 1) * t * t * t - s * t * t;
var easeInOutCubic3 = (t) => t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2;
var dampedCos = (q, freq, decay) => Math.exp(-decay * q) * Math.cos(freq * q) * (1 - q);
var dampedSin = (q, freq, decay) => Math.exp(-decay * q) * Math.sin(freq * q) * (1 - q);
var hash012 = (a, b = 0) => {
  let h = Math.imul((a | 0) ^ 2654435769, 2246822507) ^ Math.imul((b | 0) + 1663821227, 3266489909);
  h ^= h >>> 15;
  h = Math.imul(h, 739982445);
  h ^= h >>> 12;
  h = Math.imul(h, 695872825);
  h ^= h >>> 15;
  return (h >>> 0) / 4294967296;
};
var restPose = () => ({
  dx: 0,
  dy: 0,
  scaleX: 1,
  scaleY: 1,
  rotation: 0,
  alpha: 1,
  skew: 0,
  scramble: -1,
  rgbSplit: 0,
  blur: 0,
  split: 0,
  backside: false,
  reveal: 1
});
var restSing = () => ({ dx: 0, dy: 0, scale: 1, scaleX: 1, scaleY: 1, rotation: 0, flash: 0, glow: 0, color: 0 });
var applyMotion = (pose, motion) => {
  if (motion === 1) return pose;
  pose.dx *= motion;
  pose.dy *= motion;
  pose.rotation *= motion;
  pose.skew *= motion;
  pose.rgbSplit *= motion;
  pose.scaleX = 1 + (pose.scaleX - 1) * motion;
  pose.scaleY = 1 + (pose.scaleY - 1) * motion;
  return pose;
};
var scaled = (pose, scale) => {
  pose.scaleX = scale;
  pose.scaleY = scale;
  return pose;
};
var enterPose = (fx, p, ctx) => {
  const pose = restPose();
  if (p >= 1) return pose;
  const q = clamp019(p);
  const [r0, r1, r2] = ctx.rand;
  switch (fx) {
    case "pop": {
      const s = easeOutBack2(q, 2.4);
      scaled(pose, s);
      pose.scaleY = s * (1 + 0.14 * dampedSin(q, 14, 3));
      pose.scaleX = s * (1 - 0.1 * dampedSin(q, 14, 3));
      pose.rotation = (r0 - 0.5) * 0.7 * (1 - easeOutCubic4(q));
      pose.dy = 0.25 * (1 - easeOutCubic4(q));
      pose.alpha = clamp019(q * 6);
      break;
    }
    case "drop": {
      if (q < 0.48) {
        const f = q / 0.48;
        pose.dy = -2.4 * (1 - f * f);
        pose.scaleY = 1 + 0.3 * f;
        pose.scaleX = 1 - 0.12 * f;
      } else {
        const f = (q - 0.48) / 0.52;
        pose.dy = -0.32 * Math.abs(Math.sin(f * Math.PI * 2)) * Math.exp(-3 * f) * (1 - f);
        pose.scaleY = 1 - 0.3 * dampedCos(f, 16, 4);
        pose.scaleX = 1 + 0.22 * dampedCos(f, 16, 4);
      }
      pose.alpha = clamp019(q * 7);
      break;
    }
    case "rise": {
      const f = clamp019(q / 0.58);
      const e = easeOutCubic4(f);
      pose.dy = 1.7 * (1 - e);
      if (q < 0.58) {
        pose.scaleY = 1 + 0.55 * (1 - e);
        pose.scaleX = 1 - 0.28 * (1 - e);
      } else {
        const g = (q - 0.58) / 0.42;
        pose.scaleY = 1 - 0.2 * dampedSin(g, 11, 2.5);
        pose.scaleX = 1 + 0.16 * dampedSin(g, 11, 2.5);
        pose.dy += 0.08 * dampedSin(g, 11, 2.5);
      }
      pose.alpha = clamp019(q * 4);
      break;
    }
    case "spin": {
      const e = easeOutBack2(q, 1.9);
      pose.rotation = -2.6 * (1 - e) * (r0 < 0.5 ? 1 : -1);
      scaled(pose, 0.15 + 0.85 * e);
      pose.dx = -0.7 * (1 - easeOutCubic4(q)) * ctx.dirX;
      pose.dy = -0.7 * (1 - easeOutCubic4(q)) * ctx.dirY - 0.3 * Math.sin(Math.PI * q) * (1 - q);
      pose.alpha = clamp019(q * 4);
      break;
    }
    case "wipe": {
      const e = easeOutCubic4(q);
      pose.reveal = easeOutCubic4(clamp019(q / 0.8));
      pose.dx = -0.35 * (1 - e) * ctx.dirX;
      pose.dy = -0.35 * (1 - e) * ctx.dirY;
      pose.skew = -0.3 * (1 - e);
      pose.alpha = clamp019(q * 8);
      break;
    }
    case "type": {
      pose.alpha = q > 0 ? 1 : 0;
      scaled(pose, 1 + 0.3 * (1 - clamp019(q / 0.6)) ** 2);
      break;
    }
    case "scramble": {
      pose.alpha = clamp019(q * 8);
      if (q < 0.72) {
        const frame2 = Math.floor(ctx.time * 22);
        pose.scramble = Math.floor(hash012(frame2, Math.floor(r0 * 1e6)) * 1e6);
        pose.dy = (hash012(frame2 + 7, Math.floor(r1 * 1e6)) - 0.5) * 0.12;
        pose.alpha *= 0.75 + 0.25 * hash012(frame2 + 13, 1);
      } else {
        scaled(pose, 1 + 0.16 * (1 - (q - 0.72) / 0.28) ** 2);
      }
      break;
    }
    case "stretch": {
      const k = (1 - q) ** 3;
      pose.scaleX = 1 + 2 * k - 0.16 * dampedSin(q, 13, 3);
      pose.scaleY = 1 - 0.72 * k + 0.12 * dampedSin(q, 13, 3);
      pose.dx = -1.4 * k * ctx.dirX;
      pose.dy = -1.4 * k * ctx.dirY;
      pose.alpha = clamp019(q * 5);
      break;
    }
    case "elastic": {
      const angle = r0 * Math.PI * 2;
      const spring2 = Math.exp(-4.2 * q) * Math.cos(q * Math.PI * 4.5) * (1 - q);
      pose.dx = Math.cos(angle) * 1.6 * spring2;
      pose.dy = Math.sin(angle) * 1.6 * spring2;
      pose.rotation = (r1 - 0.5) * 0.8 * spring2;
      pose.scaleX = 1 + 0.18 * Math.abs(spring2);
      pose.scaleY = 1 - 0.12 * Math.abs(spring2);
      pose.alpha = clamp019(q * 5);
      break;
    }
    case "split": {
      pose.split = 1 - easeOutExpo3(clamp019(q / 0.8));
      if (q > 0.8) {
        const g = (q - 0.8) / 0.2;
        pose.scaleX = 1 + 0.1 * dampedSin(g, 10, 2);
        pose.scaleY = 1 - 0.08 * dampedSin(g, 10, 2);
      }
      pose.alpha = clamp019(q * 5);
      break;
    }
    case "spiral": {
      const e = easeOutCubic4(q);
      const radius = 3.4 * (1 - e);
      const angle = r0 * Math.PI * 2 + Math.PI * 2.5 * (1 - e);
      pose.dx = Math.cos(angle) * radius;
      pose.dy = Math.sin(angle) * radius * 0.8;
      pose.rotation = -Math.PI * 2 * (1 - e) * (r1 < 0.5 ? 1 : -1);
      scaled(pose, 0.25 + 0.75 * easeOutBack2(q, 1.5));
      pose.alpha = clamp019(q * 3);
      break;
    }
    case "flip": {
      const phi = Math.PI * 2.5 * (1 - easeOutCubic4(q));
      pose.scaleX = Math.cos(phi);
      pose.backside = pose.scaleX < 0;
      pose.scaleY = 1 + 0.08 * Math.sin(phi);
      pose.dy = -0.3 * Math.sin(Math.PI * q) * (1 - q);
      pose.alpha = clamp019(q * 6);
      break;
    }
    case "glitch": {
      if (q < 0.8) {
        const frame2 = Math.floor(ctx.time * 24);
        const seed = Math.floor(r0 * 1e6);
        const intensity = 1 - q / 0.8;
        const h1 = hash012(frame2, seed), h2 = hash012(frame2, seed + 1), h3 = hash012(frame2, seed + 2), h4 = hash012(frame2, seed + 3);
        pose.dx = h2 > 0.35 ? (h1 - 0.5) * 0.9 * intensity : 0;
        pose.rgbSplit = (0.05 + 0.13 * h3) * intensity;
        pose.skew = h4 > 0.7 ? (h1 - 0.5) * 0.9 * intensity : 0;
        pose.scaleX = h2 > 0.82 ? 1 + 0.4 * intensity : 1;
        pose.alpha = clamp019(q * 10) * (hash012(frame2, seed + 4) > 0.18 ? 1 : 0.25);
      }
      break;
    }
    case "stamp": {
      if (q < STAMP_IMPACT) {
        const f = q / STAMP_IMPACT;
        scaled(pose, 2.6 - 1.6 * easeInQuad(f));
        pose.rotation = (r0 - 0.5) * 0.35 * (1 - f);
        pose.alpha = clamp019(f * 2.2);
      } else {
        const f = (q - STAMP_IMPACT) / (1 - STAMP_IMPACT);
        pose.scaleX = 1 + 0.22 * dampedCos(f, 17, 4);
        pose.scaleY = 1 - 0.22 * dampedCos(f, 17, 4);
      }
      break;
    }
    case "wave": {
      const k = (1 - q) ** 1.5;
      pose.dy = 1.1 * k * Math.cos(q * Math.PI * 3);
      pose.rotation = 0.4 * k * Math.sin(q * Math.PI * 3);
      pose.scaleY = 1 + 0.18 * k * Math.sin(q * Math.PI * 3 + 0.6);
      pose.alpha = clamp019(q * 4);
      break;
    }
    case "zoom": {
      const e = easeOutExpo3(q);
      const k = 1.8 * (1 - e);
      scaled(pose, 1 + k * 1.5);
      pose.dx = -ctx.toCenterX * k;
      pose.dy = -ctx.toCenterY * k;
      pose.blur = (1 - q) ** 1.4;
      pose.alpha = clamp019(q * 3.5);
      break;
    }
    case "burst": {
      const e = easeOutBack2(q, 1.8);
      pose.dx = ctx.toCenterX * (1 - e);
      pose.dy = ctx.toCenterY * (1 - e);
      scaled(pose, 0.2 + 0.8 * easeOutBack2(clamp019(q * 1.3), 1.6));
      pose.rotation = (r2 - 0.5) * 4 * (1 - easeOutCubic4(q));
      pose.alpha = clamp019(q * 6);
      break;
    }
  }
  return applyMotion(pose, ctx.motion);
};
var exitPose = (fx, p, ctx) => {
  const pose = restPose();
  if (p <= 0) return pose;
  const q = clamp019(p);
  const [r0, r1, r2] = ctx.rand;
  switch (fx) {
    case "ascend": {
      const e = easeInCubic2(q);
      const dip = q < 0.22 ? Math.sin(q / 0.22 * Math.PI) * 0.12 : 0;
      pose.dy = dip - 2.8 * e;
      pose.dx = (r0 - 0.5) * 0.7 * e;
      pose.rotation = (r1 - 0.5) * 0.5 * e;
      pose.scaleY = 1 + 0.45 * e;
      pose.scaleX = 1 - 0.22 * e;
      pose.alpha = 1 - easeInQuad(q);
      break;
    }
    case "scatter": {
      let ox = -ctx.toCenterX + (r0 - 0.5) * 2;
      let oy = -ctx.toCenterY + (r1 - 0.5) * 2;
      const len = Math.hypot(ox, oy) || 1;
      ox /= len;
      oy /= len;
      const e = easeOutCubic4(q);
      const dist = 2.4 + r2 * 1.8;
      pose.dx = ox * dist * e;
      pose.dy = oy * dist * e;
      pose.rotation = (r1 - 0.5) * 3.2 * e;
      scaled(pose, 1 - 0.65 * e);
      pose.alpha = 1 - q ** 1.6;
      break;
    }
    case "shrink": {
      const s = q < 0.2 ? 1 + 0.16 * Math.sin(q / 0.2 * Math.PI / 2) : 1.16 * (1 - easeInBack2((q - 0.2) / 0.8, 1.4));
      scaled(pose, Math.max(0, s));
      pose.rotation = (r0 - 0.5) * 0.9 * q;
      pose.alpha = q > 0.8 ? (1 - q) / 0.2 : 1;
      break;
    }
    case "slide": {
      const e = easeInBack2(q, 1.6);
      const dist = ctx.slideDistance ?? 7;
      pose.dx = ctx.dirX * dist * e;
      pose.dy = ctx.dirY * dist * e;
      pose.scaleX = 1 + 0.45 * easeInQuad(q) * Math.abs(ctx.dirX);
      pose.scaleY = 1 + 0.45 * easeInQuad(q) * Math.abs(ctx.dirY);
      pose.skew = -0.45 * easeInQuad(q) * Math.sign(ctx.dirX || 1);
      pose.alpha = 1 - clamp019((q - 0.45) / 0.55) ** 1.5;
      break;
    }
    case "dissolve": {
      const frame2 = Math.floor(ctx.time * 20);
      const flicker = hash012(frame2, Math.floor(r0 * 1e6));
      pose.alpha = (1 - q) ** 1.3 * (1 - 0.45 * q * flicker);
      scaled(pose, 1 + 0.14 * easeOutQuad(q));
      pose.dy = -0.35 * easeOutQuad(q);
      pose.blur = q;
      break;
    }
    case "fall": {
      const e = easeInQuad(q);
      pose.dy = 3 * e;
      pose.dx = 0.28 * Math.sin(q * Math.PI * 2 + r0 * 6) * q;
      pose.rotation = (r1 - 0.5) * 1.2 * e;
      pose.scaleY = 1 + 0.4 * e;
      pose.scaleX = 1 - 0.25 * e;
      pose.alpha = 1 - q ** 1.6;
      break;
    }
    case "blink": {
      const on = q < 0.14 || q >= 0.24 && q < 0.4 || q >= 0.5 && q < 0.6 || q >= 0.7 && q < 0.76 || q >= 0.82 && q < 0.85;
      pose.alpha = on && q < 1 ? 1 : 0;
      scaled(pose, 1 + (on ? 0.05 * q : 0));
      break;
    }
  }
  if (q >= 1) pose.alpha = 0;
  return applyMotion(pose, ctx.motion);
};
var singPose = (fx, u, duration, rand, motion) => {
  const pose = restSing();
  if (u < 0 || fx === "none") return pose;
  const hold = Math.max(duration, 0.12);
  const envelope = clamp019(u / 0.08) * (1 - clamp019((u - hold) / 0.35));
  switch (fx) {
    case "bounce": {
      const T = 0.3;
      if (u < T) pose.dy = -0.26 * Math.sin(u / T * Math.PI);
      else if (u < T + 0.16) pose.dy = -0.06 * Math.sin((u - T) / 0.16 * Math.PI);
      const land = u - T;
      if (land >= 0 && land < 0.3) {
        const f = land / 0.3;
        pose.scaleY = 1 - 0.14 * dampedCos(f, 14, 3);
        pose.scaleX = 1 + 0.1 * dampedCos(f, 14, 3);
      } else if (u < T) {
        pose.scaleY = 1 + 0.08 * Math.sin(u / T * Math.PI);
      }
      break;
    }
    case "flash": {
      pose.flash = Math.exp(-u / 0.16);
      pose.scale = 1 + 0.2 * Math.exp(-u / 0.1) * clamp019(u / 0.03);
      break;
    }
    case "swell": {
      pose.scale = 1 + 0.24 * easeOutBack2(clamp019(u / 0.18), 2) * (1 - clamp019((u - hold) / 0.35));
      break;
    }
    case "shake": {
      const decay = Math.exp(-Math.max(0, u - hold) / 0.08);
      const k = clamp019(u / 0.04) * decay * (u < hold + 0.4 ? 1 : 0);
      pose.dx = 0.06 * Math.sin(u * 61 + rand * 9) * k;
      pose.dy = 0.04 * Math.sin(u * 47 + rand * 5) * k;
      pose.rotation = 0.08 * Math.sin(u * 53 + rand * 7) * k;
      break;
    }
    case "jump": {
      const T = 0.42;
      if (u < T) {
        const f = u / T;
        pose.dy = -0.5 * Math.sin(f * Math.PI);
        pose.rotation = (rand < 0.5 ? 1 : -1) * 0.22 * Math.sin(f * Math.PI * 2) * (1 - f);
        pose.scaleY = 1 + 0.2 * Math.sin(f * Math.PI) * (1 - f);
        pose.scaleX = 1 - 0.12 * Math.sin(f * Math.PI) * (1 - f);
      } else if (u < T + 0.35) {
        const f = (u - T) / 0.35;
        pose.scaleY = 1 - 0.2 * dampedCos(f, 13, 3);
        pose.scaleX = 1 + 0.16 * dampedCos(f, 13, 3);
      }
      break;
    }
    case "glow": {
      pose.glow = envelope;
      pose.flash = 0.35 * envelope;
      pose.scale = 1 + 0.07 * envelope;
      break;
    }
    case "underline": {
      pose.dy = -0.05 * envelope;
      break;
    }
    case "color": {
      pose.color = clamp019(u / 0.1);
      pose.scale = 1 + 0.14 * Math.exp(-u / 0.12) * clamp019(u / 0.03);
      break;
    }
  }
  if (motion !== 1) {
    pose.dx *= motion;
    pose.dy *= motion;
    pose.rotation *= motion;
    pose.scale = 1 + (pose.scale - 1) * motion;
    pose.scaleX = 1 + (pose.scaleX - 1) * motion;
    pose.scaleY = 1 + (pose.scaleY - 1) * motion;
  }
  return pose;
};
var combinePoses = (a, b, out = restPose()) => {
  out.dx = a.dx + b.dx;
  out.dy = a.dy + b.dy;
  out.scaleX = a.scaleX * b.scaleX;
  out.scaleY = a.scaleY * b.scaleY;
  out.rotation = a.rotation + b.rotation;
  out.alpha = a.alpha * b.alpha;
  out.skew = a.skew + b.skew;
  out.scramble = a.scramble >= 0 ? a.scramble : b.scramble;
  out.rgbSplit = a.rgbSplit + b.rgbSplit;
  out.blur = Math.max(a.blur, b.blur);
  out.split = Math.max(a.split, b.split);
  out.backside = a.backside || b.backside;
  out.reveal = Math.min(a.reveal, b.reveal);
  return out;
};
var enterOrder = (fx, count, rand) => {
  const order = Array.from({ length: count }, (_, index) => index);
  if (fx === "scramble" || fx === "glitch") {
    for (let i = count - 1; i > 0; i -= 1) {
      const j = Math.floor(rand() * (i + 1));
      [order[i], order[j]] = [order[j], order[i]];
    }
    const rank = new Array(count);
    order.forEach((glyph, k) => {
      rank[glyph] = k;
    });
    return rank;
  }
  if (fx === "zoom" || fx === "burst") {
    const mid = (count - 1) / 2;
    return order.map((index) => Math.round(Math.abs(index - mid) * 2) / 2);
  }
  return order;
};
var STAGGER_FACTOR = { burst: 0.35, zoom: 0.6, stamp: 1.35, type: 1 };
var scheduleEnter = (fx, ranks, enterAt, stagger, deadline) => {
  const maxRank = ranks.reduce((max, rank) => Math.max(max, rank), 0);
  let step = Math.max(0, stagger) * (STAGGER_FACTOR[fx] ?? 1);
  let duration = ENTER_DURATION[fx];
  const available = deadline - enterAt;
  if (step * maxRank + duration > available) {
    step = maxRank > 0 ? Math.max(0, Math.min(step, (available - duration) / maxRank)) : 0;
    if (step * maxRank + duration > available) {
      const ratio = Math.max(0, available) / (step * maxRank + duration);
      step *= ratio;
      duration = Math.max(0.1, duration * ratio);
      if (step * maxRank + duration > available) step = maxRank > 0 ? Math.max(0, (available - duration) / maxRank) : 0;
    }
  }
  const start = ranks.map((rank) => rank < 0 ? Number.NaN : enterAt + rank * step);
  return { start, duration, landed: start.map((value) => value + duration) };
};
var scheduleExit = (ranks, exitAt, exitDuration) => {
  const maxRank = ranks.reduce((max, rank) => Math.max(max, rank), 0);
  const total = Math.max(1e-3, exitDuration);
  const step = maxRank > 0 ? Math.min(0.05, total * 0.4 / maxRank) : 0;
  const each = total - step * maxRank;
  const start = ranks.map((rank) => rank < 0 ? Number.NaN : exitAt + rank * step);
  return { start, end: start.map((value) => value + each) };
};
var stampShake = (time, impacts, amplitude) => {
  let x = 0;
  let y = 0;
  for (let i = 0; i < impacts.length; i += 1) {
    const tau = time - impacts[i];
    if (tau < 0 || tau > 0.45) continue;
    const k = amplitude * Math.exp(-tau / 0.085);
    x += k * Math.sin(tau * 96 + i * 1.7);
    y += k * 0.8 * Math.sin(tau * 77 + i * 2.3 + 1);
  }
  return { x, y };
};

// folia:src/components/visualizer/hanabi/text/blocks.ts
var blockLayoutParams = (style, hardShadow) => {
  const base = {
    none: { tracking: 0.02, wordGap: 0.12, lineHeight: 1.12, minAdvance: 0, stairStep: 0, padding: 0.1 },
    tile: { tracking: 0.14, wordGap: 0.12, lineHeight: 1.3, minAdvance: 0.86, stairStep: 0, padding: 0.1 },
    band: { tracking: 0.04, wordGap: 0.14, lineHeight: 1.42, minAdvance: 0, stairStep: 0, padding: 0.3 },
    slant: { tracking: 0.04, wordGap: 0.72, lineHeight: 1.42, minAdvance: 0, stairStep: 0, padding: 0.36 },
    double: { tracking: 0.04, wordGap: 0.68, lineHeight: 1.5, minAdvance: 0, stairStep: 0, padding: 0.4 },
    pill: { tracking: 0.04, wordGap: 0.6, lineHeight: 1.42, minAdvance: 0, stairStep: 0, padding: 0.4 },
    split: { tracking: 0.04, wordGap: 0.58, lineHeight: 1.42, minAdvance: 0, stairStep: 0, padding: 0.3 },
    ticket: { tracking: 0.05, wordGap: 0.72, lineHeight: 1.48, minAdvance: 0, stairStep: 0, padding: 0.45 },
    marker: { tracking: 0.03, wordGap: 0.14, lineHeight: 1.3, minAdvance: 0, stairStep: 0, padding: 0.14 },
    outline: { tracking: 0.04, wordGap: 0.3, lineHeight: 1.55, minAdvance: 0, stairStep: 0, padding: 0.32 },
    circle: { tracking: 0.24, wordGap: 0.14, lineHeight: 1.4, minAdvance: 0.95, stairStep: 0, padding: 0.12 },
    stair: { tracking: 0.06, wordGap: 0.12, lineHeight: 1.6, minAdvance: 0.82, stairStep: 0.16, padding: 0.3 }
  };
  const params = { ...base[style] };
  if (hardShadow) params.padding += 0.08;
  return params;
};
var blockTextRole = (style) => style === "none" || style === "outline" || style === "marker" ? "paper" : "ink";
var darken = (color, amount) => {
  const k = 1 - amount;
  const r = Math.round((color >> 16 & 255) * k);
  const g = Math.round((color >> 8 & 255) * k);
  const b = Math.round((color & 255) * k);
  return r << 16 | g << 8 | b;
};
var runFrame = (glyphs, indices, padL, padT) => {
  const members = indices.map((index) => glyphs[index]).filter((glyph) => !glyph.blank);
  if (members.length === 0) return null;
  let sin = 0;
  let cos = 0;
  members.forEach((glyph) => {
    sin += Math.sin(glyph.angle);
    cos += Math.cos(glyph.angle);
  });
  const angle = Math.atan2(sin, cos);
  const tx = Math.cos(angle), ty = Math.sin(angle);
  const nx = -ty, ny = tx;
  const origin = members[0];
  let minT = Infinity, maxT = -Infinity, minN = Infinity, maxN = -Infinity;
  let curved = false;
  members.forEach((glyph) => {
    if (Math.abs(Math.atan2(Math.sin(glyph.angle - angle), Math.cos(glyph.angle - angle))) > 0.08) curved = true;
    const px = glyph.x - origin.x, py = glyph.y - origin.y;
    const pt = px * tx + py * ty;
    const pn = px * nx + py * ny;
    minT = Math.min(minT, pt - glyph.advance / 2);
    maxT = Math.max(maxT, pt + glyph.advance / 2);
    minN = Math.min(minN, pn - glyph.size * 0.56);
    maxN = Math.max(maxN, pn + glyph.size * 0.56);
  });
  const midT = (minT + maxT) / 2;
  const midN = (minN + maxN) / 2;
  const thickness = maxN - minN + padT * 2;
  const frame2 = {
    cx: origin.x + tx * midT + nx * midN,
    cy: origin.y + ty * midT + ny * midN,
    angle,
    length: maxT - minT + padL * 2,
    thickness,
    curved,
    points: []
  };
  if (curved) {
    const edge = (glyph, side, extra) => ({
      x: glyph.x + Math.cos(glyph.angle) * (glyph.advance / 2 + extra) * side,
      y: glyph.y + Math.sin(glyph.angle) * (glyph.advance / 2 + extra) * side,
      nx: -Math.sin(glyph.angle),
      ny: Math.cos(glyph.angle)
    });
    const raw = [edge(members[0], -1, padL)];
    for (let k = 1; k < members.length; k += 1) {
      const a = edge(members[k - 1], 1, 0), b = edge(members[k], -1, 0);
      raw.push({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, nx: (a.nx + b.nx) / 2, ny: (a.ny + b.ny) / 2 });
    }
    raw.push(edge(members[members.length - 1], 1, padL));
    let s = 0;
    frame2.points = raw.map((point, index) => {
      if (index > 0) s += Math.hypot(point.x - raw[index - 1].x, point.y - raw[index - 1].y);
      const len = Math.hypot(point.nx, point.ny) || 1;
      return { x: point.x, y: point.y, nx: point.nx / len, ny: point.ny / len, s };
    });
  }
  return frame2;
};
var SWEEP = /* @__PURE__ */ new Set(["band", "slant", "double", "marker", "outline"]);
var easeOutCubic5 = (t) => 1 - (1 - t) ** 3;
var easeOutQuart = (t) => 1 - (1 - t) ** 4;
var easeOutExpo4 = (t) => t >= 1 ? 1 : 1 - 2 ** (-10 * t);
var easeOutBack3 = (t, s = 1.70158) => 1 + (s + 1) * (t - 1) ** 3 + s * (t - 1) ** 2;
var createBlocks = (options) => {
  const { pixi, style, placement, palette } = options;
  const view = new pixi.Container();
  view.label = "hanabi-blocks";
  const back = new pixi.Container();
  const front = new pixi.Container();
  view.addChild(back, front);
  const colors = palette.blocks.length > 0 ? palette.blocks : [palette.accent];
  const colorAt = (index) => colors[(index % colors.length + colors.length) % colors.length];
  const second = (index) => colors.length > 1 ? colorAt(index + 1) : darken(colorAt(index), 0.35);
  const glyphColor = /* @__PURE__ */ new Map();
  const pieces = [];
  const rng = createRng2(`${options.seed}:blocks`);
  const glyphs = placement.glyphs;
  const fontPx = placement.fontPx;
  const makeGraphics = (layer) => {
    const g = new pixi.Graphics();
    layer.addChild(g);
    return g;
  };
  const timesOf = (indices) => {
    let first = Infinity, last = -Infinity, exitStart = Infinity, exitEnd = -Infinity;
    indices.forEach((index) => {
      const start = options.enterStart[index];
      if (!Number.isFinite(start)) return;
      first = Math.min(first, start);
      last = Math.max(last, start);
      exitStart = Math.min(exitStart, options.exitStart[index]);
      exitEnd = Math.max(exitEnd, options.exitEnd[index]);
    });
    return { first, last, exitStart, exitEnd };
  };
  const newPiece = (partsSpec, anchor, frame2, timing) => {
    const piece = {
      parts: partsSpec.map((spec) => ({ g: makeGraphics(spec.layer), lag: spec.lag ?? 0, ox: spec.ox ?? 0, oy: spec.oy ?? 0, slide: spec.slide ?? 0 })),
      anchor,
      ...frame2,
      ...timing,
      rand: [rng(), rng(), rng(), rng()],
      toCenterX: (options.centerX - frame2.x) / Math.max(1, frame2.unit),
      toCenterY: (options.centerY - frame2.y) / Math.max(1, frame2.unit),
      lastKey: ""
    };
    pieces.push(piece);
    return piece;
  };
  const perGlyph = style === "tile" || style === "circle" || style === "stair" || style === "marker";
  const stairDrop = /* @__PURE__ */ new Map();
  if (style === "stair") {
    const groups = /* @__PURE__ */ new Map();
    glyphs.forEach((glyph, index) => {
      if (glyph.blank) return;
      const key = `${glyph.row}:${glyph.word}`;
      groups.set(key, [...groups.get(key) ?? [], index]);
    });
    groups.forEach((indices) => {
      const first = glyphs[indices[0]];
      const nx = -Math.sin(first.angle), ny = Math.cos(first.angle);
      const bottoms = indices.map((index) => {
        const glyph = glyphs[index];
        return (glyph.x - first.x) * nx + (glyph.y - first.y) * ny + glyph.size * 0.56;
      });
      const lowest = Math.max(...bottoms);
      indices.forEach((index, k) => stairDrop.set(index, lowest - bottoms[k]));
    });
  }
  if (perGlyph) {
    let ordinal = 0;
    glyphs.forEach((glyph, index) => {
      if (glyph.blank || !Number.isFinite(options.enterStart[index])) return;
      const color = style === "marker" ? colorAt(glyph.word) : colorAt(ordinal);
      ordinal += 1;
      const start = options.enterStart[index];
      const timing = {
        enterStart: start - (style === "marker" ? 0 : 0.05),
        enterDur: style === "marker" ? 0.28 : 0.34,
        exitStart: options.exitStart[index],
        exitEnd: options.exitEnd[index]
      };
      const size = glyph.size;
      if (style === "tile" || style === "circle") {
        const piece2 = newPiece(
          [{ layer: front }],
          "center",
          { x: glyph.x, y: glyph.y, angle: glyph.rotation, length: glyph.boxW, thickness: glyph.boxH, unit: size },
          timing
        );
        const g2 = piece2.parts[0].g;
        if (style === "tile") {
          const inset = size * 0.035;
          g2.roundRect(-glyph.boxW / 2 + inset, -glyph.boxH / 2, glyph.boxW - inset * 2, glyph.boxH, size * 0.06).fill({ color: 16777215 });
        } else {
          g2.circle(0, 0, Math.max(size * 0.64, Math.max(glyph.boxW, glyph.boxH) * 0.5)).fill({ color: 16777215 });
        }
        g2.tint = color;
        glyphColor.set(index, color);
        return;
      }
      const tx = Math.cos(glyph.angle), ty = Math.sin(glyph.angle);
      const nx = -ty, ny = tx;
      if (style === "stair") {
        const h = size * 1.12;
        const depth = size * 0.3 + (stairDrop.get(index) ?? 0);
        const piece2 = newPiece([{ layer: front }], "bottom", {
          x: glyph.x + nx * (h / 2 + depth),
          y: glyph.y + ny * (h / 2 + depth),
          angle: glyph.angle,
          length: glyph.advance,
          thickness: h + depth,
          unit: size
        }, timing);
        const g2 = piece2.parts[0].g;
        g2.rect(-glyph.advance / 2, -(h + depth), glyph.advance, h + depth).fill({ color: 16777215 });
        g2.rect(-glyph.advance / 2, -(h + depth), glyph.advance, size * 0.07).fill({ color: 16777215, alpha: 0.45 });
        g2.tint = color;
        glyphColor.set(index, color);
        return;
      }
      const L = glyph.advance + size * 0.08;
      const piece = newPiece([{ layer: front }], "start", {
        x: glyph.x - tx * L / 2,
        y: glyph.y - ty * L / 2,
        angle: glyph.angle,
        length: L,
        thickness: size * 0.5,
        unit: size
      }, timing);
      const g = piece.parts[0].g;
      const top = size * 0.06;
      const bottom = size * 0.58;
      const wob = size * 0.06;
      g.poly([wob, top + wob * 0.5, L, top, L - wob, bottom, 0, bottom - wob * 0.4]).fill({ color: 16777215, alpha: 0.92 });
      g.tint = color;
      glyphColor.set(index, color);
    });
  }
  const perWord = style === "slant" || style === "double" || style === "pill" || style === "split" || style === "ticket";
  if (perWord) {
    const groups = [];
    glyphs.forEach((glyph, index) => {
      if (glyph.blank) return;
      const punct = options.words[glyph.word]?.blank ?? false;
      const last = groups[groups.length - 1];
      const lastGlyph = last ? glyphs[last.indices[last.indices.length - 1]] : null;
      if (last && lastGlyph && lastGlyph.row === glyph.row && (last.word === glyph.word || punct)) {
        last.indices.push(index);
        return;
      }
      groups.push({ indices: [index], word: glyph.word });
    });
    groups.forEach((group, ordinal) => {
      const frame2 = runFrame(glyphs, group.indices, fontPx * (style === "pill" ? 0.26 : 0.2), fontPx * 0.1);
      if (!frame2) return;
      const times = timesOf(group.indices);
      if (!Number.isFinite(times.first)) return;
      const color = colorAt(ordinal);
      const color2 = second(ordinal);
      const L = frame2.length;
      const T = frame2.thickness;
      const tx = Math.cos(frame2.angle), ty = Math.sin(frame2.angle);
      const sweep = style === "slant" || style === "double";
      const timing = {
        enterStart: times.first - 0.08,
        enterDur: sweep ? times.last - times.first + 0.42 : 0.44,
        exitStart: times.exitStart,
        exitEnd: times.exitEnd
      };
      const base = sweep ? { x: frame2.cx - tx * L / 2, y: frame2.cy - ty * L / 2, angle: frame2.angle, length: L, thickness: T, unit: T / 1.3 } : { x: frame2.cx, y: frame2.cy, angle: frame2.angle, length: L, thickness: T, unit: T / 1.3 };
      group.indices.forEach((index) => glyphColor.set(index, color));
      if (style === "slant") {
        const piece = newPiece([{ layer: front }], "start", base, timing);
        const sk = T * 0.36;
        piece.parts[0].g.poly([sk / 2, -T / 2, L + sk / 2, -T / 2, L - sk / 2, T / 2, -sk / 2, T / 2]).fill({ color: 16777215 });
        piece.parts[0].g.tint = color;
      } else if (style === "double") {
        const off = T * 0.13;
        const piece = newPiece([{ layer: back, lag: 0.09, ox: off, oy: off * 1.1 }, { layer: front }], "start", base, timing);
        piece.parts.forEach((part, k) => {
          part.g.rect(0, -T / 2, L, T).fill({ color: 16777215 });
          part.g.tint = k === 0 ? color2 : color;
        });
      } else if (style === "pill") {
        const piece = newPiece([{ layer: front }], "center", base, timing);
        piece.parts[0].g.roundRect(-L / 2, -T / 2, L, T, T / 2).fill({ color: 16777215 });
        piece.parts[0].g.tint = color;
      } else if (style === "split") {
        const piece = newPiece([{ layer: front, slide: -1 }, { layer: front, slide: 1 }], "center", base, timing);
        piece.parts[0].g.rect(-L / 2, -T / 2, L, T / 2 + 0.5).fill({ color: 16777215 });
        piece.parts[0].g.tint = color;
        piece.parts[1].g.rect(-L / 2, 0, L, T / 2).fill({ color: 16777215 });
        piece.parts[1].g.tint = color2;
      } else {
        const piece = newPiece([{ layer: front }], "center", base, timing);
        const g = piece.parts[0].g;
        const r = T * 0.2;
        g.moveTo(-L / 2, -T / 2).lineTo(L / 2, -T / 2).lineTo(L / 2, -r).arc(L / 2, 0, r, -Math.PI / 2, Math.PI / 2, true).lineTo(L / 2, T / 2).lineTo(-L / 2, T / 2).lineTo(-L / 2, r).arc(-L / 2, 0, r, Math.PI / 2, -Math.PI / 2, true).closePath().fill({ color: 16777215 });
        const stubX = L / 2 - Math.min(T * 0.62, L * 0.2);
        for (let y = -T / 2 + T * 0.14; y < T / 2 - T * 0.1; y += T * 0.16) {
          g.circle(stubX, y, Math.max(0.8, T * 0.028)).fill({ color: 0, alpha: 0.28 });
        }
        g.tint = color;
      }
    });
  }
  if (style === "band" || style === "outline") {
    placement.rows.forEach((row, rowIndex) => {
      const padL = fontPx * (style === "band" ? 0.32 : 0.26);
      const padT = fontPx * (style === "band" ? 0.12 : 0.16);
      const frame2 = runFrame(glyphs, row, padL, padT);
      if (!frame2) return;
      const times = timesOf(row);
      if (!Number.isFinite(times.first)) return;
      const color = colorAt(rowIndex);
      row.forEach((index) => {
        if (!glyphs[index].blank) glyphColor.set(index, color);
      });
      const L = frame2.length;
      const T = frame2.thickness;
      const tx = Math.cos(frame2.angle), ty = Math.sin(frame2.angle);
      const timing = {
        enterStart: times.first - 0.1,
        enterDur: times.last - times.first + 0.45,
        exitStart: times.exitStart,
        exitEnd: times.exitEnd
      };
      if (style === "band" && frame2.curved) {
        const piece2 = newPiece([{ layer: front }], "center", { x: 0, y: 0, angle: 0, length: L, thickness: T, unit: T / 1.3 }, timing);
        piece2.toCenterX = 0;
        piece2.toCenterY = 0;
        const points = frame2.points;
        const total = points[points.length - 1].s || 1;
        piece2.redraw = (g, a, b, thick) => {
          g.clear();
          if (b <= a) return;
          const sa = a * total, sb = b * total;
          const at = (s) => {
            let k = 1;
            while (k < points.length - 1 && points[k].s < s) k += 1;
            const p0 = points[k - 1], p1 = points[k];
            const f = p1.s > p0.s ? clamp019((s - p0.s) / (p1.s - p0.s)) : 0;
            return {
              x: p0.x + (p1.x - p0.x) * f,
              y: p0.y + (p1.y - p0.y) * f,
              nx: p0.nx + (p1.nx - p0.nx) * f,
              ny: p0.ny + (p1.ny - p0.ny) * f
            };
          };
          const spine = [at(sa), ...points.filter((point) => point.s > sa && point.s < sb), at(sb)];
          const half = T / 2 * thick;
          const top = [];
          spine.forEach((point) => top.push(point.x - point.nx * half, point.y - point.ny * half));
          const back2 = [];
          for (let k = spine.length - 1; k >= 0; k -= 1) {
            const point = spine[k];
            back2.push(point.x + point.nx * half, point.y + point.ny * half);
          }
          g.poly([...top, ...back2]).fill({ color: 16777215 });
        };
        piece2.parts[0].g.tint = color;
        return;
      }
      if (style === "band") {
        const piece2 = newPiece(
          [{ layer: front }],
          "start",
          { x: frame2.cx - tx * L / 2, y: frame2.cy - ty * L / 2, angle: frame2.angle, length: L, thickness: T, unit: T / 1.3 },
          timing
        );
        const g = piece2.parts[0].g;
        g.rect(0, -T / 2, L, T).fill({ color });
        if (colors.length > 1) g.rect(0, T / 2 - T * 0.1, L, T * 0.1).fill({ color: second(rowIndex) });
        return;
      }
      const piece = newPiece(
        [{ layer: front }],
        "center",
        { x: frame2.cx, y: frame2.cy, angle: frame2.angle, length: L, thickness: T, unit: T / 1.3 },
        timing
      );
      const stroke = Math.max(1.5, T * 0.07);
      const perimeter = 2 * (L + T);
      const corners = [[-L / 2, -T / 2], [L / 2, -T / 2], [L / 2, T / 2], [-L / 2, T / 2]];
      const trace = (g, startCorner, from, to) => {
        let travelled = 0;
        let started = false;
        for (let k = 0; k < 4 && travelled < to * perimeter; k += 1) {
          const a = corners[(startCorner + k) % 4];
          const b = corners[(startCorner + k + 1) % 4];
          const seg = Math.hypot(b[0] - a[0], b[1] - a[1]);
          const s0 = Math.max(from * perimeter, travelled);
          const s1 = Math.min(to * perimeter, travelled + seg);
          if (s1 > s0) {
            const f0 = (s0 - travelled) / seg, f1 = (s1 - travelled) / seg;
            const x0 = a[0] + (b[0] - a[0]) * f0, y0 = a[1] + (b[1] - a[1]) * f0;
            const x1 = a[0] + (b[0] - a[0]) * f1, y1 = a[1] + (b[1] - a[1]) * f1;
            if (!started) {
              g.moveTo(x0, y0);
              started = true;
            }
            g.lineTo(x1, y1);
          }
          travelled += seg;
        }
        if (started) g.stroke({ width: stroke, color: 16777215, join: "miter", cap: "square" });
      };
      piece.redraw = (g, a, b) => {
        g.clear();
        if (b <= a) return;
        trace(g, 0, a / 2, b / 2);
        trace(g, 2, a / 2, b / 2);
      };
      piece.parts[0].g.tint = color;
    });
  }
  const exitContext = (piece, time) => ({
    index: 0,
    count: 1,
    rand: piece.rand,
    toCenterX: piece.toCenterX,
    toCenterY: piece.toCenterY,
    dirX: Math.cos(piece.angle),
    dirY: Math.sin(piece.angle),
    time,
    motion: options.motion,
    slideDistance: 7
  });
  const update = (time) => {
    pieces.forEach((piece) => {
      piece.parts.forEach((part) => {
        const g = part.g;
        const t = time - part.lag;
        if (t < piece.enterStart || t >= piece.exitEnd) {
          g.visible = false;
          return;
        }
        const q = clamp019((t - piece.enterStart) / Math.max(1e-3, piece.enterDur));
        const xq = piece.exitEnd > piece.exitStart ? clamp019((t - piece.exitStart) / (piece.exitEnd - piece.exitStart)) : 0;
        const tx = Math.cos(piece.angle), ty = Math.sin(piece.angle);
        let sx = 1, sy = 1, rot = 0, alpha = 1, dx = 0, dy = 0;
        let a = 0, b = 1;
        switch (style) {
          case "tile": {
            const s = easeOutBack3(q, 2.2);
            sx = s;
            sy = s;
            rot = (piece.rand[0] - 0.5) * 0.6 * (1 - easeOutCubic5(q));
            alpha = clamp019(q * 5);
            break;
          }
          case "circle": {
            const s = q >= 1 ? 1 : 1 - Math.cos(q * Math.PI * 3.5) * Math.exp(-5 * q) * (1 - q);
            sx = s;
            sy = s;
            alpha = clamp019(q * 5);
            break;
          }
          case "stair":
            sy = Math.max(0, easeOutBack3(q, 1.8));
            alpha = clamp019(q * 6);
            break;
          case "marker":
            b = easeOutCubic5(q);
            break;
          case "band":
            b = easeOutQuart(q);
            sy = q < 0.22 ? 0.14 : 0.14 + 0.86 * easeOutBack3((q - 0.22) / 0.78, 1.8);
            break;
          case "slant":
          case "double":
            b = easeOutExpo4(q);
            break;
          case "outline":
            b = easeInOutCubic3(q);
            break;
          case "pill":
            sx = 0.2 + 0.8 * easeOutBack3(q, 1.4);
            sy = Math.max(0, easeOutBack3(clamp019(q * 1.5), 2.2));
            alpha = clamp019(q * 4);
            break;
          case "split": {
            const e = easeOutExpo4(q);
            dx = tx * part.slide * (1 - e) * piece.length * 0.7;
            dy = ty * part.slide * (1 - e) * piece.length * 0.7;
            alpha = clamp019(q * 4);
            break;
          }
          case "ticket":
            sy = Math.max(0, easeOutBack3(q, 2.5));
            sx = 0.7 + 0.3 * easeOutCubic5(q);
            rot = -0.25 * (1 - easeOutCubic5(q));
            alpha = clamp019(q * 4);
            break;
          case "none":
            break;
        }
        if (xq > 0) {
          if (SWEEP.has(style)) {
            a = Math.max(a, easeInOutCubic3(xq));
            if (options.exit === "blink" || options.exit === "dissolve") alpha *= exitPose(options.exit, xq, exitContext(piece, t - piece.exitStart)).alpha;
            else alpha *= 1 - clamp019((xq - 0.85) / 0.15);
          } else {
            const pose = exitPose(options.exit, xq, exitContext(piece, t - piece.exitStart));
            dx += pose.dx * piece.unit;
            dy += pose.dy * piece.unit;
            rot += pose.rotation * (perGlyph ? 1 : 0.4);
            sx *= pose.scaleX;
            sy *= pose.scaleY;
            alpha *= pose.alpha;
          }
        }
        if (b <= a || alpha <= 1e-3) {
          g.visible = false;
          return;
        }
        g.visible = true;
        g.alpha = alpha * options.opacity;
        if (piece.redraw) {
          const key = `${a.toFixed(4)}:${b.toFixed(4)}:${sy.toFixed(4)}`;
          if (key !== piece.lastKey) {
            piece.lastKey = key;
            piece.redraw(g, a, b, sy);
          }
          g.position.set(piece.x + dx, piece.y + dy);
          g.rotation = piece.angle + rot;
          g.scale.set(sx, style === "outline" ? sy : 1);
          return;
        }
        let px = piece.x + dx + part.ox;
        let py = piece.y + dy + part.oy;
        if (piece.anchor === "start") {
          px += tx * piece.length * a;
          py += ty * piece.length * a;
          sx *= b - a;
        }
        g.position.set(px, py);
        g.rotation = piece.angle + rot;
        g.scale.set(sx, sy);
      });
    });
  };
  return {
    view,
    update,
    colorOf: (glyph) => glyphColor.get(glyph) ?? null,
    destroy: () => {
      view.destroy({ children: true, context: true });
    }
  };
};

// folia:src/components/visualizer/hanabi/text/glyphs.ts
var UPRIGHT2 = /[ᄀ-ᇿ⺀-⿿　-〿぀-ヿ㄀-ㇿ㈀-鿿가-힯豈-﫿︰-﹏＀-￯]|[\u{20000}-\u{3134f}]/u;
var isUprightGlyph2 = (char) => UPRIGHT2.test(char);
var hasCjk = (text) => UPRIGHT2.test(text);
var glyphFont2 = (weight, px, family2) => `${weight} ${px}px ${family2}`;
var estimateAdvance = (char) => {
  if (char.trim().length === 0) return 0.3;
  if (isUprightGlyph2(char)) return 1;
  if (/[ilI.,:;'!|]/.test(char)) return 0.34;
  if (/[mwMW@]/.test(char)) return 0.85;
  return 0.6;
};
var createContext = () => {
  try {
    if (typeof OffscreenCanvas !== "undefined") {
      const context = new OffscreenCanvas(8, 8).getContext("2d");
      if (context) return context;
    }
    if (typeof document !== "undefined") return document.createElement("canvas").getContext("2d");
  } catch {
  }
  return null;
};
var createGlyphMeasure = (font, weight) => {
  const context = createContext();
  const cache2 = /* @__PURE__ */ new Map();
  if (context) context.font = glyphFont2(weight, 100, font);
  return (char) => {
    let width = cache2.get(char);
    if (width === void 0) {
      width = context ? context.measureText(char).width / 100 : estimateAdvance(char);
      if (!Number.isFinite(width) || width <= 0) width = estimateAdvance(char);
      cache2.set(char, width);
    }
    return width;
  };
};
var ATLAS_BASE_LIMIT_PX = 4096;
var ATLAS_HARD_LIMIT_PX = 8192;
var gpuTextureLimitPx = 4096;
var setHanabiGlyphTextureLimit = (px) => {
  if (Number.isFinite(px) && px >= 2048) gpuTextureLimitPx = Math.floor(px);
};
var resolveGlyphAtlasLimit = (resolution, maxCanvasPx, devicePixelRatio = globalThis.devicePixelRatio ?? 1) => {
  if (maxCanvasPx !== void 0) return maxCanvasPx;
  const superscale = Math.max(1, resolution / resolveHanabiBaseResolution(devicePixelRatio));
  return Math.min(ATLAS_BASE_LIMIT_PX * superscale, Math.max(ATLAS_BASE_LIMIT_PX, gpuTextureLimitPx), ATLAS_HARD_LIMIT_PX);
};
var cellSide = (px, outline, glow) => Math.ceil(px * 1.3 + 2 * Math.max(outline * px, glow ? px * 0.32 : 0) + 4);
var buildGlyphAtlas = (pixi, options) => {
  const variants = ["fill"];
  if (options.outline > 0) variants.push("fat");
  if (options.glow) variants.push("glow");
  const cells2 = [];
  const add = (char, px, scramble) => {
    const side = cellSide(px, options.outline, options.glow);
    const kinds = scramble ? variants.filter((v) => v !== "glow") : variants;
    kinds.forEach((variant) => cells2.push({ char, px, variant, side, x: 0, y: 0, scramble }));
  };
  options.chars.forEach((px, char) => {
    if (char.trim().length > 0) add(char, Math.max(4, px), false);
  });
  options.scramble?.chars.forEach((char) => add(char, Math.max(4, options.scramble.px), true));
  const gap = 2;
  const area = cells2.reduce((sum, cell) => sum + (cell.side + gap) ** 2, 0);
  const maxSide = cells2.reduce((max, cell) => Math.max(max, cell.side), 1);
  const shelfWidth = Math.max(maxSide + gap, Math.ceil(Math.sqrt(area) * 1.15));
  const order = cells2.map((_, index) => index).sort((a, b) => cells2[b].side - cells2[a].side);
  let x = 0;
  let y = 0;
  let shelf = 0;
  let width = 1;
  order.forEach((index) => {
    const cell = cells2[index];
    if (x + cell.side > shelfWidth && x > 0) {
      x = 0;
      y += shelf + gap;
      shelf = 0;
    }
    cell.x = x;
    cell.y = y;
    x += cell.side + gap;
    shelf = Math.max(shelf, cell.side);
    width = Math.max(width, x);
  });
  const height = Math.max(1, y + shelf);
  const limit = resolveGlyphAtlasLimit(options.resolution, options.maxCanvasPx);
  const resolution = Math.max(0.1, Math.min(options.resolution, limit / width, limit / height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.ceil(width * resolution));
  canvas.height = Math.max(1, Math.ceil(height * resolution));
  const source = new pixi.CanvasSource({ resource: canvas, resolution });
  let painted = false;
  const paint = () => {
    if (painted) return false;
    painted = true;
    const context = canvas.getContext("2d");
    context.setTransform(resolution, 0, 0, resolution, 0, 0);
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.fillStyle = "#ffffff";
    context.strokeStyle = "#ffffff";
    context.lineJoin = "round";
    cells2.forEach((cell) => {
      context.font = glyphFont2(options.weight, cell.px, options.font);
      const cx = cell.x + cell.side / 2;
      const cy = cell.y + cell.side / 2;
      if (cell.variant === "fat") {
        context.lineWidth = options.outline * cell.px * 2;
        context.strokeText(cell.char, cx, cy);
        context.fillText(cell.char, cx, cy);
      } else if (cell.variant === "glow") {
        context.save();
        context.shadowColor = "#ffffff";
        context.shadowBlur = cell.px * 0.22 * resolution;
        context.globalAlpha = 0.85;
        context.fillText(cell.char, cx, cy);
        context.fillText(cell.char, cx, cy);
        context.restore();
      } else {
        context.fillText(cell.char, cx, cy);
      }
    });
    source.update();
    return true;
  };
  const textures = [];
  const sub = (fx, fy, fw, fh) => {
    const texture = new pixi.Texture({ source, frame: new pixi.Rectangle(fx, fy, fw, fh) });
    textures.push(texture);
    return texture;
  };
  const entries = /* @__PURE__ */ new Map();
  const scrambleEntries = /* @__PURE__ */ new Map();
  cells2.forEach((cell) => {
    const map = cell.scramble ? scrambleEntries : entries;
    let entry = map.get(cell.char);
    if (!entry) {
      entry = { char: cell.char, px: cell.px, fill: null, fat: null, glow: null, halves: null };
      map.set(cell.char, entry);
    }
    const texture = sub(cell.x, cell.y, cell.side, cell.side);
    if (cell.variant === "fill") {
      entry.fill = texture;
      if (options.halves && !cell.scramble) {
        const half = cell.side / 2;
        entry.halves = options.halves === "lr" ? [sub(cell.x, cell.y, half, cell.side), sub(cell.x + half, cell.y, half, cell.side)] : [sub(cell.x, cell.y, cell.side, half), sub(cell.x, cell.y + half, cell.side, half)];
      }
    } else if (cell.variant === "fat") entry.fat = texture;
    else entry.glow = texture;
  });
  const blank = { char: " ", px: 1, fill: pixi.Texture.EMPTY, fat: null, glow: null, halves: null };
  return {
    entry: (char) => entries.get(char) ?? blank,
    scramble: options.scramble?.chars.map((char) => scrambleEntries.get(char)).filter(Boolean) ?? [],
    paint,
    destroy: () => {
      textures.forEach((texture) => texture.destroy(false));
      source.destroy();
    }
  };
};
var SCRAMBLE_KANA = Array.from("\u30A2\u30A4\u30A6\u30A8\u30AA\u30AB\u30AD\u30AF\u30B1\u30B3\u30B5\u30B7\u30B9\u30BB\u30BD\u30BF\u30C1\u30C4\u30C6\u30C8\u30CA\u30CB\u30CC\u30CD\u30CF\u30D2\u30D5\u30D8\u30DB\u30DE\u30DF\u30E0\u30E1\u30E2\u30E4\u30E6\u30E8\u30E9\u30EA\u30EB\u30EC\u30ED\u30EF\u30F2\u30F3\uFF03\uFF05\uFF06\uFF0A\uFF1F\uFF01\u25C6\u203B");
var SCRAMBLE_LATIN = Array.from("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#%&*?!<>/+=");
var pickScrambleChars = (text, count, random) => {
  const pool = [...hasCjk(text) ? SCRAMBLE_KANA : SCRAMBLE_LATIN];
  const picked = [];
  while (picked.length < count && pool.length > 0) {
    picked.push(pool.splice(Math.floor(random() * pool.length), 1)[0]);
  }
  return picked;
};

// folia:src/components/visualizer/hanabi/text/layout.ts
var FUNCTION_WORDS2 = new Set(Array.from("\u7684\u4E86\u5728\u628A\u662F\u6211\u4F60\u4ED6\u5979\u5B83\u4EEC\u548C\u4E0E\u4E5F\u5C31\u90FD\u7740\u8FC7\u5417\u5462\u5427\u554A\u5440\u54E6\u88AB\u8BA9\u7ED9\u4ECE\u5411\u5230\u8FD9\u90A3\u4E4B\u800C\u53C8\u5F88\u306E\u306F\u304C\u3092\u306B\u3067\u3068\u3082\u3078\u3084\u306D\u3088\u304B\u306A"));
var MINOR_LATIN2 = /* @__PURE__ */ new Set(["a", "an", "the", "of", "to", "in", "on", "at", "me", "my", "with", "and", "or", "is", "i", "you", "it", "by", "for"]);
var wordScales2 = (words, emphasis, seed) => {
  const rng = createRng2(`${seed}:word-scale`);
  const e = Math.max(0, Math.min(1, emphasis));
  const lengthOf = (text) => Array.from(text).length;
  const minor = (word) => word.blank || lengthOf(word.text) === 1 && FUNCTION_WORDS2.has(word.text) || MINOR_LATIN2.has(word.text.toLowerCase());
  let key = -1;
  words.forEach((word, index) => {
    if (minor(word)) return;
    if (key < 0 || lengthOf(word.text) >= lengthOf(words[key].text)) key = index;
  });
  const solid = words.filter((word) => !word.blank).length;
  return words.map((word, index) => {
    const jitter = rng();
    if (word.space) return 1;
    if (word.blank) return 1 - 0.2 * e;
    if (solid <= 1) return 1;
    if (index === key) return 1 + 0.8 * e;
    if (minor(word)) return Math.max(0.6, 1 - 0.32 * e);
    return 1 + (jitter - 0.5) * 0.45 * e;
  });
};
var ROTATE_IN_VERTICAL = new Set(Array.from("\u30FC\u2014\u2015\u2500\uFF5E\u301C\u2026\u2025\uFF0D-_=~"));
var rotate = (x, y, angle) => {
  const c = Math.cos(angle);
  const s = Math.sin(angle);
  return { x: x * c - y * s, y: x * s + y * c };
};
var buildUnits = (glyphs, words) => {
  const units = [];
  words.forEach((word, index) => {
    if (word.end <= word.start) return;
    const last = units[units.length - 1];
    if (word.blank && !word.space && last && !last.space) {
      last.words.push(index);
      return;
    }
    units.push({ words: [index], space: word.space });
  });
  if (units.length > 1 && !units[0].space && units[0].words.every((index) => words[index].blank)) {
    const first = units.shift();
    units[0].words.unshift(...first.words);
    units[0].space = false;
  }
  return units.map((unit) => {
    const indices = [];
    unit.words.forEach((index) => {
      for (let g = words[index].start; g < words[index].end; g += 1) if (g < glyphs.length) indices.push(g);
    });
    return { glyphs: indices, space: unit.space };
  });
};
var partitionRuns = (units, gaps, k, breakPenalty) => {
  const n = units.length;
  if (n === 0) return [];
  const parts = Math.max(1, Math.min(k, units.filter((unit) => !unit.space).length || 1));
  const spanLength = (from, to) => {
    let a = from;
    let b = to;
    while (a <= b && units[a].space) a += 1;
    while (b >= a && units[b].space) b -= 1;
    let total = 0;
    for (let i = a; i <= b; i += 1) total += units[i].length + (i > a ? gaps[i] : 0);
    return total;
  };
  const INF = Number.POSITIVE_INFINITY;
  const best = Array.from({ length: parts + 1 }, () => new Array(n + 1).fill(INF));
  const cut = Array.from({ length: parts + 1 }, () => new Array(n + 1).fill(0));
  best[0][0] = 0;
  for (let p2 = 1; p2 <= parts; p2 += 1) {
    for (let j2 = 1; j2 <= n; j2 += 1) {
      for (let i = p2 - 1; i < j2; i += 1) {
        if (best[p2 - 1][i] === INF) continue;
        let solid = false;
        for (let u = i; u < j2; u += 1) if (!units[u].space) solid = true;
        if (!solid) continue;
        const value = Math.max(best[p2 - 1][i], spanLength(i, j2 - 1) + (i > 0 ? breakPenalty?.[i] ?? 0 : 0));
        if (value < best[p2][j2] - 1e-9) {
          best[p2][j2] = value;
          cut[p2][j2] = i;
        }
      }
    }
  }
  let p = parts;
  while (p > 1 && best[p][n] === INF) p -= 1;
  const runs = [];
  let j = n;
  for (let q = p; q >= 1; q -= 1) {
    const i = cut[q][j];
    runs.unshift(Array.from({ length: j - i }, (_, offset) => i + offset));
    j = i;
  }
  return runs;
};
var layoutText = (glyphInputs, words, params) => {
  const { layout, regionWidth: W, regionHeight: H, fontPx } = params;
  const rng = createRng2(`${params.seed}:layout`);
  const vertical = layout === "vertical" || layout === "vertical-split";
  const count = glyphInputs.length;
  const sizes = glyphInputs.map((glyph) => fontPx * (words[glyph.word]?.scale ?? 1));
  const turned = glyphInputs.map((glyph) => vertical && (!glyph.upright || ROTATE_IN_VERTICAL.has(glyph.char)));
  const along = glyphInputs.map((glyph, index) => {
    const size = sizes[index];
    if (glyph.blank) return glyph.advance * size;
    if (vertical && !turned[index]) return size * (1 + params.tracking * 0.6);
    return (Math.max(glyph.advance, vertical ? 0 : params.minAdvance) + params.tracking) * size;
  });
  const work = glyphInputs.map((_, index) => ({
    x: 0,
    y: 0,
    size: sizes[index],
    advance: along[index],
    angle: 0,
    rotation: 0,
    boxW: 0,
    boxH: 0,
    row: 0
  }));
  const unitList = buildUnits(glyphInputs, words);
  const units = unitList.map((unit) => ({
    glyphs: unit.glyphs,
    space: unit.space,
    length: unit.glyphs.reduce((sum, index) => sum + along[index], 0),
    thickness: unit.glyphs.reduce((max, index) => glyphInputs[index].blank ? max : Math.max(max, sizes[index]), 0) || fontPx
  }));
  const gaps = units.map((unit, index) => index > 0 && !unit.space && !units[index - 1].space ? params.wordGap * fontPx : 0);
  const penalties = units.map((unit) => {
    const first = glyphInputs[unit.glyphs[0] ?? 0]?.char ?? "";
    return /^[぀-ゟ゠-ヿー、。，．！？]/.test(first) ? fontPx * 1.2 : 0;
  });
  const rows = [];
  const flow = (unitIndices, rowIndex, place) => {
    let a = 0;
    let b = unitIndices.length - 1;
    while (a <= b && units[unitIndices[a]].space) a += 1;
    while (b >= a && units[unitIndices[b]].space) b -= 1;
    const thick = unitIndices.reduce((max, u) => Math.max(max, units[u].space ? 0 : units[u].thickness), 0) || fontPx;
    let s = 0;
    const members = [];
    for (let k = 0; k < unitIndices.length; k += 1) {
      const unit = units[unitIndices[k]];
      const outside = k < a || k > b;
      if (k > a && k <= b) s += gaps[unitIndices[k]];
      let wordStart = -1;
      let stepIndex = 0;
      unit.glyphs.forEach((glyph) => {
        const size = sizes[glyph];
        const advance = outside ? 0 : along[glyph];
        const word = glyphInputs[glyph].word;
        if (word !== wordStart) {
          wordStart = word;
          stepIndex = 0;
        }
        const settle = vertical ? 0 : (thick - size) * 0.42;
        const stair = glyphInputs[glyph].blank ? 0 : -params.stairStep * size * (stepIndex % 3);
        if (!glyphInputs[glyph].blank) stepIndex += 1;
        work[glyph].row = rowIndex;
        work[glyph].advance = advance;
        place(glyph, s + advance / 2, settle + stair);
        s += advance;
        members.push(glyph);
      });
    }
    rows[rowIndex] = members;
    return { length: s, thickness: thick };
  };
  const runLength = (unitIndices) => {
    let a = 0;
    let b = unitIndices.length - 1;
    while (a <= b && units[unitIndices[a]].space) a += 1;
    while (b >= a && units[unitIndices[b]].space) b -= 1;
    let total = 0;
    for (let k = a; k <= b; k += 1) total += units[unitIndices[k]].length + (k > a ? gaps[unitIndices[k]] : 0);
    return total;
  };
  const runThickness = (unitIndices) => unitIndices.reduce((max, u) => Math.max(max, units[u].space ? 0 : units[u].thickness), 0) || fontPx;
  const chooseRuns = (kMin, kMax, main, cross, pitch) => {
    let bestRuns = [];
    let bestFit = -1;
    for (let k = kMin; k <= kMax; k += 1) {
      const runs = partitionRuns(units, gaps, k, penalties);
      if (runs.length < Math.min(k, kMin)) continue;
      const longest = Math.max(...runs.map(runLength), 1);
      const across = runs.reduce((sum, run) => sum + runThickness(run) * pitch, 0);
      const fit2 = Math.min(1, main / longest, cross / across);
      if (fit2 > bestFit * 1.08 || bestRuns.length === 0) {
        bestFit = fit2;
        bestRuns = runs;
      }
      if (fit2 >= 1) break;
    }
    return bestRuns;
  };
  const solidUnits = units.filter((unit) => !unit.space).length;
  const chunkUnits = () => {
    const chunks = [];
    units.forEach((unit, index) => {
      if (unit.space) return;
      const last = chunks[chunks.length - 1];
      const text = unit.glyphs.map((glyph) => glyphInputs[glyph].char).join("");
      const kana = unit.glyphs.length === 1 && /^[぀-ゟ゠-ヿー]$/.test(text);
      const lastLength = last ? last.reduce((sum, u) => sum + units[u].glyphs.length, 0) : 0;
      if (last && kana && lastLength < 5) last.push(index);
      else chunks.push([index]);
    });
    return chunks;
  };
  const placeStraight = (glyph, x, y, rowIndex) => {
    const w = work[glyph];
    w.x = x;
    w.y = y;
    w.row = rowIndex;
  };
  switch (layout) {
    case "center":
    case "left":
    case "right":
    case "stagger":
    case "diagonal": {
      let kMin = 1;
      let kMax = layout === "diagonal" ? 2 : 3;
      if (layout === "stagger") {
        kMin = Math.min(solidUnits, solidUnits >= 5 ? 3 : 2);
        kMax = Math.min(solidUnits, 3);
        kMin = Math.max(1, kMin);
        kMax = Math.max(kMin, kMax);
      }
      const slope = layout === "diagonal" ? -Math.min(0.42, Math.max(0.2, Math.atan2(H * 0.7, W))) : 0;
      const runs = chooseRuns(kMin, kMax, layout === "diagonal" ? W * 0.95 : W, H, params.lineHeight);
      const pitchFactor = layout === "stagger" ? params.lineHeight * 0.94 : params.lineHeight;
      let cursorY = 0;
      const lengths = runs.map(runLength);
      const longest = Math.max(...lengths, 1);
      const staggerAmp = fontPx * (0.9 + rng() * 0.6);
      runs.forEach((run, rowIndex) => {
        const thick = runThickness(run);
        if (rowIndex > 0) cursorY += thick * pitchFactor * 0.5;
        const L = lengths[rowIndex];
        let x0;
        if (layout === "left") x0 = 0;
        else if (layout === "right") x0 = -L;
        else if (layout === "stagger") {
          const room = Math.max(0, (longest - L) / 2);
          const side = rowIndex % 2 === 0 ? -1 : 1;
          x0 = -L / 2 + side * Math.max(staggerAmp, room * 0.9) * (runs.length === 1 ? 0 : 1);
        } else x0 = -L / 2;
        const rowY = cursorY;
        flow(run, rowIndex, (glyph, s, n) => {
          if (layout === "diagonal") {
            const x = x0 + s;
            placeStraight(glyph, x, rowY + n + (x - (x0 + L / 2)) * Math.tan(slope), rowIndex);
            const w = work[glyph];
            w.advance /= Math.cos(slope);
            w.angle = slope;
            w.rotation = slope * 0.3;
          } else placeStraight(glyph, x0 + s, rowY + n, rowIndex);
        });
        cursorY += thick * pitchFactor * 0.5;
      });
      break;
    }
    case "arc": {
      const runs = chooseRuns(1, 2, W * 0.95, H, params.lineHeight);
      const lengths = runs.map(runLength);
      const longest = Math.max(...lengths, 1);
      const radius0 = Math.max(longest / 1.3, W * 0.62);
      let depth = 0;
      runs.forEach((run, rowIndex) => {
        const thick = runThickness(run);
        if (rowIndex > 0) depth += thick * params.lineHeight * 0.5;
        const R = Math.max(radius0 - depth, longest / 2.6);
        const L = lengths[rowIndex];
        const centerY = radius0;
        flow(run, rowIndex, (glyph, s, n) => {
          const a = (s - L / 2) / R;
          const r = R - n;
          const w = work[glyph];
          w.x = r * Math.sin(a);
          w.y = centerY - r * Math.cos(a);
          w.angle = a;
          w.rotation = a;
        });
        depth += thick * params.lineHeight * 0.5;
      });
      break;
    }
    case "vertical": {
      const runs = chooseRuns(1, 4, H, W, params.lineHeight);
      let cursorX = 0;
      runs.forEach((run, colIndex) => {
        const thick = runThickness(run);
        if (colIndex > 0) cursorX -= thick * params.lineHeight * 0.5;
        const colX = cursorX;
        flow(run, colIndex, (glyph, s, n) => {
          const w = work[glyph];
          w.x = colX - n;
          w.y = s;
          w.angle = Math.PI / 2;
          w.rotation = turned[glyph] ? Math.PI / 2 : 0;
        });
        cursorX -= thick * params.lineHeight * 0.5;
      });
      break;
    }
    case "vertical-split": {
      const chunks = chunkUnits();
      const lengths = chunks.map(runLength);
      const estimate = (groups2) => {
        const per2 = Math.ceil(chunks.length / groups2);
        return Math.max(1, ...Array.from({ length: groups2 }, (_, g) => lengths.slice(g * per2, (g + 1) * per2).reduce((sum, length) => sum + length * 0.6, 0)));
      };
      let groups = 1;
      while (groups < 3 && estimate(groups) > H && chunks.length > groups * 2) groups += 1;
      const per = Math.ceil(chunks.length / groups) || 1;
      let cursorX = 0;
      let runIndex = 0;
      for (let g = 0; g < groups; g += 1) {
        const members = chunks.slice(g * per, (g + 1) * per);
        const memberLengths = lengths.slice(g * per, (g + 1) * per);
        if (members.length === 0) continue;
        const thick = Math.max(...members.map(runThickness));
        const pitch = thick * params.lineHeight;
        if (g > 0) cursorX -= pitch * 1.1;
        const tops = [];
        const ends = [];
        members.forEach((chunk, k) => {
          const side = k % 2 === 0 ? 0.5 : -0.5;
          let top = 0;
          if (k >= 1) top = Math.max(top, tops[k - 1] + memberLengths[k - 1] * 0.5);
          if (k >= 2) top = Math.max(top, ends[k - 2] + fontPx * 0.2);
          tops.push(top);
          ends.push(top + memberLengths[k]);
          const colX = cursorX + side * pitch * (members.length > 1 ? 1 : 0) - pitch * 0.5;
          flow(chunk, runIndex, (glyph, s, n) => {
            const w = work[glyph];
            w.x = colX - n;
            w.y = top + s;
            w.angle = Math.PI / 2;
            w.rotation = turned[glyph] ? Math.PI / 2 : 0;
          });
          runIndex += 1;
        });
        cursorX -= pitch;
      }
      break;
    }
    case "scatter": {
      const chunks = chunkUnits();
      const pad = params.padding * fontPx;
      const extra = chunks.map(() => 0.8 + rng() * 0.5);
      const rotations = chunks.map(() => (rng() - 0.5) * 0.16);
      const gapsAfter = chunks.map(() => fontPx * (0.35 + rng() * 0.8));
      const jitterRand = chunks.map(() => rng() * 2 - 1);
      const dims = chunks.map((chunk, k) => {
        const w = runLength(chunk) * extra[k] + pad * 2;
        const h = runThickness(chunk) * extra[k] * (1.12 + params.stairStep * 4) + pad * 2;
        const c = Math.abs(Math.cos(rotations[k]));
        const s = Math.abs(Math.sin(rotations[k]));
        return { w, h, aabbW: w * c + h * s, aabbH: w * s + h * c };
      });
      const n = chunks.length;
      let bestRows = [];
      let bestScore = -Infinity;
      for (let r = 1; r <= Math.min(4, n); r += 1) {
        const rowsOf = partitionRuns(dims.map((d) => ({ length: d.aabbW, space: false })), dims.map((_, k) => k > 0 ? gapsAfter[k - 1] : 0), r);
        const widths2 = rowsOf.map((row) => row.reduce((sum, k, i) => sum + dims[k].aabbW + (i > 0 ? gapsAfter[k - 1] : 0), 0));
        const heights = rowsOf.map((row) => Math.max(...row.map((k) => dims[k].aabbH)) * 1.5);
        const fit2 = Math.min(1, W / Math.max(...widths2), H / heights.reduce((sum, h) => sum + h, 0));
        const score = fit2 + (n >= 3 && rowsOf.length >= 2 ? 0.08 : 0) + (rowsOf.length === Math.min(3, n) ? 0.04 : 0);
        if (score > bestScore) {
          bestScore = score;
          bestRows = rowsOf;
        }
      }
      const rowHeights = bestRows.map((row) => Math.max(...row.map((k) => dims[k].aabbH)));
      const widths = bestRows.map((row) => row.reduce((sum, k, i) => sum + dims[k].aabbW + (i > 0 ? gapsAfter[k - 1] : 0), 0));
      const widest = Math.max(...widths, 1);
      let cursorY = 0;
      bestRows.forEach((row, r) => {
        const rowH = rowHeights[r];
        const jitter = rowH * 0.22;
        if (r > 0) cursorY += rowHeights[r - 1] / 2 + rowH / 2 + (rowHeights[r - 1] * 0.22 + jitter) + fontPx * 0.1;
        const slack = Math.max(0, widest - widths[r]);
        let cursorX = -widths[r] / 2 + (rng() - 0.5) * (slack + fontPx * 1.2) * (bestRows.length > 1 ? 1 : 0);
        row.forEach((k, i) => {
          if (i > 0) cursorX += gapsAfter[k - 1];
          const d = dims[k];
          const cx = cursorX + d.aabbW / 2;
          const cy = cursorY + jitterRand[k] * (jitter + (rowH - d.aabbH) * 0.5);
          cursorX += d.aabbW;
          const chunk = chunks[k];
          const L = runLength(chunk) * extra[k];
          const angle = rotations[k];
          flow(chunk, k, (glyph, s, nOffset) => {
            const w = work[glyph];
            const local = rotate(s * extra[k] - L / 2, nOffset * extra[k], angle);
            w.x = cx + local.x;
            w.y = cy + local.y;
            w.angle = angle;
            w.rotation = angle;
            w.size = sizes[glyph] * extra[k];
            w.advance *= extra[k];
          });
        });
      });
      break;
    }
  }
  if (layout === "scatter" || layout === "vertical-split") {
    units.forEach((unit) => {
      if (!unit.space) return;
      unit.glyphs.forEach((glyph) => {
        const prev = work[Math.max(0, glyph - 1)];
        const w = work[glyph];
        w.x = prev.x;
        w.y = prev.y;
        w.angle = prev.angle;
        w.rotation = prev.rotation;
        w.advance = 0;
        w.row = prev.row;
      });
    });
  }
  work.forEach((w, index) => {
    const verticalUpright = vertical && !turned[index];
    w.boxW = verticalUpright ? w.size * 1.12 : Math.max(w.advance, 0.01);
    w.boxH = verticalUpright ? Math.max(w.advance, 0.01) : w.size * 1.12;
    if (layout === "diagonal") {
      w.boxW = Math.max(w.advance * Math.cos(w.angle), 0.01);
    }
  });
  if (params.tilt) {
    work.forEach((w) => {
      const p = rotate(w.x, w.y, params.tilt);
      w.x = p.x;
      w.y = p.y;
      w.angle += params.tilt;
      w.rotation += params.tilt;
    });
  }
  const measure = () => {
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    work.forEach((w, index) => {
      if (glyphInputs[index].blank) return;
      const pad = params.padding * w.size;
      const hw = w.boxW / 2 + pad;
      const hh = w.boxH / 2 + pad;
      const c = Math.abs(Math.cos(w.rotation));
      const s = Math.abs(Math.sin(w.rotation));
      const ex = hw * c + hh * s;
      const ey = hw * s + hh * c;
      minX = Math.min(minX, w.x - ex);
      maxX = Math.max(maxX, w.x + ex);
      minY = Math.min(minY, w.y - ey);
      maxY = Math.max(maxY, w.y + ey);
    });
    if (!Number.isFinite(minX)) return { minX: 0, minY: 0, maxX: 0, maxY: 0 };
    return { minX, minY, maxX, maxY };
  };
  let box = measure();
  const fit = Math.min(1, W / Math.max(1e-6, box.maxX - box.minX), H / Math.max(1e-6, box.maxY - box.minY));
  if (fit < 1) {
    work.forEach((w) => {
      w.x *= fit;
      w.y *= fit;
      w.size *= fit;
      w.advance *= fit;
      w.boxW *= fit;
      w.boxH *= fit;
    });
    box = measure();
  }
  const shiftX = layout === "left" ? -W / 2 - box.minX : layout === "right" ? W / 2 - box.maxX : -(box.minX + box.maxX) / 2;
  const shiftY = -(box.minY + box.maxY) / 2;
  work.forEach((w) => {
    w.x += shiftX;
    w.y += shiftY;
  });
  const placed = work.map((w, index) => ({
    char: glyphInputs[index].char,
    x: w.x,
    y: w.y,
    size: w.size,
    advance: w.advance,
    angle: w.angle,
    rotation: w.rotation,
    boxW: w.boxW,
    boxH: w.boxH,
    row: w.row,
    word: glyphInputs[index].word,
    blank: glyphInputs[index].blank
  }));
  return {
    glyphs: placed,
    rows: rows.filter(Boolean).map((run) => run.filter((index) => index < count)),
    fontPx: fontPx * fit,
    fit,
    bounds: {
      x: box.minX + shiftX,
      y: box.minY + shiftY,
      width: box.maxX - box.minX,
      height: box.maxY - box.minY
    },
    vertical
  };
};

// folia:src/components/visualizer/hanabi/text/lyricText.ts
var lineWords = (line2, count) => {
  const words = [];
  let cursor = 0;
  segmentLyricWords(line2).forEach((segment2) => {
    const length = splitLyricGraphemes(segment2.segment).length;
    if (length === 0) return;
    const space = segment2.segment.trim().length === 0;
    words.push({ text: segment2.segment, start: cursor, end: cursor + length, blank: space || !segment2.isWordLike, space, scale: 1 });
    cursor += length;
  });
  if (cursor === count) return words;
  return splitLyricGraphemes(line2.fullText).map((char, index) => {
    const space = char.trim().length === 0;
    return { text: char, start: index, end: index + 1, blank: space || !/[\p{L}\p{N}]/u.test(char), space, scale: 1 };
  });
};
var mixColor2 = (a, b, t) => {
  if (t <= 0) return a;
  if (t >= 1) return b;
  const r = (a >> 16 & 255) + ((b >> 16 & 255) - (a >> 16 & 255)) * t;
  const g = (a >> 8 & 255) + ((b >> 8 & 255) - (a >> 8 & 255)) * t;
  const bl = (a & 255) + ((b & 255) - (a & 255)) * t;
  return Math.round(r) << 16 | Math.round(g) << 8 | Math.round(bl);
};
var OUTLINE_WIDTH = 0.085;
var SHADOW_OFFSET_X = 0.07;
var SHADOW_OFFSET_Y = 0.085;
var SHADOW_LAG = 0.045;
var REST_POSE = restPose();
var REST_SING = restSing();
var buildHanabiText = (options, deps = {}) => {
  const { pixi, spec, palette, line: line2 } = options;
  const motion = Math.max(0, options.motion);
  const font = resolveThemeFontStack(options.theme);
  const weight = resolveThemeFontWeight(options.theme, 800);
  const measure = deps.measure ?? createGlyphMeasure(font, weight);
  const rng = createRng2(`${options.seed}:text`);
  const timeline = buildLineGraphemeTimeline(line2);
  const chars = timeline.map((item) => item.char);
  const words = lineWords(line2, chars.length);
  const scales = wordScales2(words, spec.emphasis, options.seed);
  words.forEach((word, index) => {
    word.scale = scales[index];
  });
  const glyphWord = new Array(chars.length).fill(0);
  words.forEach((word, index) => {
    for (let g = word.start; g < word.end; g += 1) glyphWord[g] = index;
  });
  const inputs = chars.map((char, index) => ({
    char,
    advance: measure(char),
    blank: char.trim().length === 0,
    upright: isUprightGlyph2(char),
    word: glyphWord[index]
  }));
  const layoutParams = blockLayoutParams(spec.block, spec.hardShadow);
  const placement = layoutText(inputs, words, {
    layout: spec.layout,
    regionWidth: options.regionWidth,
    regionHeight: options.regionHeight,
    fontPx: spec.heroSize * Math.min(options.width, options.height),
    tilt: spec.tilt,
    seed: options.seed,
    ...layoutParams
  });
  const glyphs = placement.glyphs;
  const centerX = placement.bounds.x + placement.bounds.width / 2;
  const centerY = placement.bounds.y + placement.bounds.height / 2;
  const visibleIndices = glyphs.map((glyph, index) => glyph.blank ? -1 : index).filter((index) => index >= 0);
  const visibleCount = visibleIndices.length;
  const orderRanks = enterOrder(spec.enter, visibleCount, rng);
  const enterRanks = new Array(chars.length).fill(-1);
  visibleIndices.forEach((index, ordinal) => {
    enterRanks[index] = orderRanks[ordinal];
  });
  const firstSung = visibleIndices.reduce((min, index) => Math.min(min, timeline[index].startTime), Number.POSITIVE_INFINITY);
  const deadline = Number.isFinite(firstSung) ? firstSung : line2.startTime;
  const enter = scheduleEnter(spec.enter, enterRanks, options.enterAt, spec.stagger, deadline);
  const exitRanks = new Array(chars.length).fill(-1);
  const exitShuffle = spec.exit === "scatter" || spec.exit === "dissolve" ? enterOrder("scramble", visibleCount, createRng2(`${options.seed}:exit-order`)) : visibleIndices.map((_, ordinal) => ordinal);
  visibleIndices.forEach((index, ordinal) => {
    exitRanks[index] = exitShuffle[ordinal];
  });
  const exit = scheduleExit(exitRanks, options.exitAt, options.exitDuration);
  const view = new pixi.Container();
  view.label = "hanabi-text";
  const blocksRoot = new pixi.Container({ isRenderGroup: true });
  blocksRoot.label = "hanabi-text-blocks";
  const glyphsRoot = new pixi.Container({ isRenderGroup: true });
  glyphsRoot.label = "hanabi-text-glyphs";
  view.addChild(blocksRoot, glyphsRoot);
  const blocksInner = new pixi.Container();
  const glyphsInner = new pixi.Container();
  blocksRoot.addChild(blocksInner);
  glyphsRoot.addChild(glyphsInner);
  const masked = new pixi.Container();
  const shadowLayer = new pixi.Container();
  const outlineLayer = new pixi.Container();
  const haloLayer = new pixi.Container();
  const fxLayer = new pixi.Container();
  const mainLayer = new pixi.Container();
  const overlayLayer = new pixi.Container();
  masked.addChild(shadowLayer, outlineLayer, haloLayer, fxLayer, mainLayer);
  glyphsInner.addChild(masked, overlayLayer);
  const blocks = createBlocks({
    pixi,
    style: spec.block,
    placement,
    words,
    palette,
    opacity: clamp019(options.blockOpacity),
    motion,
    exit: spec.exit,
    seed: options.seed,
    // 色块在字差不多到位时出现。
    enterStart: enter.start.map((start) => start + enter.duration * ENTER_ARRIVAL[spec.enter]),
    exitStart: exit.start,
    exitEnd: exit.end,
    centerX,
    centerY
  });
  blocksInner.addChild(blocks.view);
  const needFx = spec.enter === "glitch" || spec.enter === "zoom" || spec.enter === "split" || spec.exit === "dissolve";
  const halvesKind = spec.enter === "split" ? placement.vertical ? "tb" : "lr" : null;
  const charPx = /* @__PURE__ */ new Map();
  let maxSize = 0;
  visibleIndices.forEach((index) => {
    const glyph = glyphs[index];
    const px = Math.ceil(glyph.size * 1.12);
    charPx.set(glyph.char, Math.max(charPx.get(glyph.char) ?? 0, px));
    maxSize = Math.max(maxSize, px);
  });
  const scrambleChars = spec.enter === "scramble" ? pickScrambleChars(line2.fullText, 14, createRng2(`${options.seed}:scramble`)) : [];
  const atlas = (deps.buildAtlas ?? buildGlyphAtlas)(pixi, {
    font,
    weight,
    resolution: options.resolution,
    chars: charPx,
    scramble: scrambleChars.length > 0 ? { chars: scrambleChars, px: maxSize } : null,
    outline: spec.outline ? OUTLINE_WIDTH : 0,
    glow: spec.sing === "glow",
    halves: halvesKind
  });
  const role = blockTextRole(spec.block);
  const baseInk = role === "ink" ? palette.ink : palette.paper;
  const firstBlock = palette.blocks[0] ?? palette.accent;
  const backdrop = hanabiBackdropOf(palette);
  const makeSprite = (layer, texture) => {
    const sprite = new pixi.Sprite(texture);
    sprite.anchor.set(0.5);
    sprite.visible = false;
    layer.addChild(sprite);
    return sprite;
  };
  const slideDistance = Math.max(options.regionWidth, options.regionHeight) * 0.8 / Math.max(1, placement.fontPx) + 3;
  const rigs = visibleIndices.map((index, ordinal) => {
    const glyph = glyphs[index];
    const entry = atlas.entry(glyph.char);
    const word = words[glyph.word];
    const keyword = options.keywordColor?.(word?.text ?? glyph.char) ?? options.keywordColor?.(glyph.char) ?? null;
    const under = blocks.colorOf(index);
    const colors = resolveHanabiGlyphColors(palette, keyword ?? baseInk, under ?? backdrop);
    const tint = colors.ink;
    const outlineTint = tint === palette.paper || under === palette.paper ? firstBlock : palette.paper;
    const shadowTint = under !== null ? darken(under, 0.42) : spec.outline && outlineTint === firstBlock ? palette.blocks[1] ?? darken(firstBlock, 0.45) : firstBlock;
    const rig2 = {
      index,
      char: glyph.char,
      x: glyph.x,
      y: glyph.y,
      size: glyph.size,
      rotation: glyph.rotation,
      angle: glyph.angle,
      entry,
      tint,
      sungTint: colors.sung,
      flashTint: colors.flash,
      backTint: colors.back,
      shadowTint,
      outlineTint,
      shadow: spec.hardShadow ? makeSprite(shadowLayer, entry.fat ?? entry.fill) : null,
      outline: spec.outline && entry.fat ? makeSprite(outlineLayer, entry.fat) : null,
      halo: spec.sing === "glow" && entry.glow ? makeSprite(haloLayer, entry.glow) : null,
      fxA: needFx ? makeSprite(fxLayer, entry.fill) : null,
      fxB: needFx ? makeSprite(fxLayer, entry.fill) : null,
      main: makeSprite(mainLayer, entry.fill),
      fxMode: "off",
      texture: entry.fill,
      enterStart: enter.start[index],
      landed: enter.landed[index],
      exitStart: exit.start[index],
      exitEnd: exit.end[index],
      sungAt: timeline[index].startTime,
      sungEnd: timeline[index].endTime,
      ctx: {
        index: ordinal,
        count: visibleCount,
        rand: [rng(), rng(), rng(), rng()],
        toCenterX: (centerX - glyph.x) / Math.max(1, glyph.size),
        toCenterY: (centerY - glyph.y) / Math.max(1, glyph.size),
        dirX: Math.cos(glyph.angle),
        dirY: Math.sin(glyph.angle),
        time: 0,
        motion,
        slideDistance
      },
      pose: restPose(),
      sing: restSing(),
      visible: false
    };
    if (rig2.shadow) rig2.shadow.tint = shadowTint;
    if (rig2.outline) rig2.outline.tint = outlineTint;
    if (rig2.halo) {
      rig2.halo.tint = palette.glow;
      rig2.halo.blendMode = "add";
    }
    rig2.main.tint = tint;
    return rig2;
  });
  const rigOf = /* @__PURE__ */ new Map();
  rigs.forEach((rig2) => rigOf.set(rig2.index, rig2));
  const impacts = [];
  if (spec.enter === "stamp") {
    const seen = /* @__PURE__ */ new Set();
    rigs.forEach((rig2) => {
      const word = glyphs[rig2.index].word;
      if (seen.has(word)) return;
      seen.add(word);
      impacts.push(rig2.enterStart + enter.duration * STAMP_IMPACT);
    });
  }
  const shakeAmplitude = placement.fontPx * 0.05 * motion;
  const cursor = spec.enter === "type" ? new pixi.Graphics() : null;
  if (cursor) {
    cursor.rect(-0.5, -0.5, 1, 1).fill({ color: 16777215 });
    cursor.tint = palette.accent;
    cursor.visible = false;
    overlayLayer.addChild(cursor);
  }
  const underlines = [];
  if (spec.sing === "underline") {
    const groups = /* @__PURE__ */ new Map();
    rigs.forEach((rig2) => {
      const glyph = glyphs[rig2.index];
      const key = `${glyph.word}`;
      const list = groups.get(key) ?? [];
      if (list.length === 0 || glyphs[list[0]].row === glyph.row) list.push(rig2.index);
      groups.set(key, list);
    });
    groups.forEach((indices) => {
      const frame2 = runFrame(glyphs, indices, 0, 0);
      if (!frame2) return;
      const members = indices.map((index) => rigOf.get(index));
      const tx = Math.cos(frame2.angle), ty = Math.sin(frame2.angle);
      const nx = -ty, ny = tx;
      const avgSize = members.reduce((sum, rig2) => sum + rig2.size, 0) / members.length;
      const thick = Math.max(3, avgSize * 0.15);
      const offset = frame2.thickness / 2 + thick * 0.4;
      const g = new pixi.Graphics();
      g.rect(0, -0.5, 1, 1).fill({ color: 16777215 });
      g.tint = members[0]?.sungTint ?? palette.accent;
      g.visible = false;
      overlayLayer.addChild(g);
      underlines.push({
        g,
        members,
        x: frame2.cx - tx * frame2.length / 2 + nx * offset,
        y: frame2.cy - ty * frame2.length / 2 + ny * offset,
        angle: frame2.angle,
        length: frame2.length,
        thick,
        from: Math.min(...members.map((rig2) => rig2.sungAt)),
        to: Math.max(...members.map((rig2) => rig2.sungEnd))
      });
    });
  }
  const wipeMask = spec.enter === "wipe" ? new pixi.Graphics() : null;
  if (wipeMask) glyphsInner.addChild(wipeMask);
  const firstStart = rigs.reduce((min, rig2) => Math.min(min, rig2.enterStart), Number.POSITIVE_INFINITY);
  const lastLanded = rigs.reduce((max, rig2) => Math.max(max, rig2.landed), Number.NEGATIVE_INFINITY);
  const scratchEnter = restPose();
  const scratchShadow = restPose();
  const evaluate = (rig2, time, lag, out, singOut) => {
    const t = time - lag;
    if (!(t >= rig2.enterStart) || t >= rig2.exitEnd) {
      Object.assign(out, REST_POSE);
      out.alpha = 0;
      if (singOut) Object.assign(singOut, REST_SING);
      return false;
    }
    rig2.ctx.time = t - rig2.enterStart;
    const a = enterPose(spec.enter, (t - rig2.enterStart) / Math.max(1e-3, enter.duration), rig2.ctx);
    Object.assign(scratchEnter, a);
    rig2.ctx.time = t - rig2.exitStart;
    const span = rig2.exitEnd - rig2.exitStart;
    const b = exitPose(spec.exit, span > 0 ? (t - rig2.exitStart) / span : 0, rig2.ctx);
    combinePoses(scratchEnter, b, out);
    if (singOut) {
      const sung = t >= rig2.landed ? singPose(spec.sing, t - rig2.sungAt, rig2.sungEnd - rig2.sungAt, rig2.ctx.rand[3], motion) : restSing();
      Object.assign(singOut, sung);
    }
    return out.alpha > 2e-3;
  };
  let evaluatedAt = Number.NaN;
  let shake = { x: 0, y: 0 };
  const evaluateAll = (time) => {
    if (time === evaluatedAt) return;
    evaluatedAt = time;
    shake = impacts.length > 0 ? stampShake(time, impacts, shakeAmplitude) : { x: 0, y: 0 };
    rigs.forEach((rig2) => {
      rig2.visible = evaluate(rig2, time, 0, rig2.pose, rig2.sing);
    });
  };
  const setTexture = (sprite, texture) => {
    if (sprite.texture !== texture) sprite.texture = texture;
  };
  const place = (sprite, x, y, rotation, sx, sy, skew, alpha) => {
    sprite.visible = alpha > 2e-3;
    if (!sprite.visible) return;
    sprite.position.set(x, y);
    sprite.rotation = rotation;
    sprite.scale.set(sx, sy);
    sprite.skew.x = skew;
    sprite.alpha = alpha;
  };
  const setFxMode = (rig2, mode) => {
    if (rig2.fxMode === mode || !rig2.fxA || !rig2.fxB) return;
    rig2.fxMode = mode;
    if (mode === "split" && rig2.entry.halves) {
      setTexture(rig2.fxA, rig2.entry.halves[0]);
      setTexture(rig2.fxB, rig2.entry.halves[1]);
      if (halvesKind === "lr") {
        rig2.fxA.anchor.set(1, 0.5);
        rig2.fxB.anchor.set(0, 0.5);
      } else {
        rig2.fxA.anchor.set(0.5, 1);
        rig2.fxB.anchor.set(0.5, 0);
      }
      rig2.fxA.blendMode = "normal";
      rig2.fxB.blendMode = "normal";
      rig2.fxA.tint = rig2.tint;
      rig2.fxB.tint = rig2.tint;
      return;
    }
    rig2.fxA.anchor.set(0.5);
    rig2.fxB.anchor.set(0.5);
    if (mode === "rgb") {
      rig2.fxA.blendMode = "add";
      rig2.fxB.blendMode = "add";
      rig2.fxA.tint = 16722e3;
      rig2.fxB.tint = 2156799;
    } else {
      rig2.fxA.blendMode = "normal";
      rig2.fxB.blendMode = "normal";
      rig2.fxA.tint = rig2.tint;
      rig2.fxB.tint = rig2.tint;
    }
  };
  const update = (time) => {
    atlas.paint?.();
    evaluateAll(time);
    blocksInner.position.set(shake.x, shake.y);
    glyphsInner.position.set(shake.x, shake.y);
    blocks.update(time);
    rigs.forEach((rig2) => {
      const pose = rig2.pose;
      const sing = rig2.sing;
      if (!rig2.visible) {
        rig2.main.visible = false;
        if (rig2.shadow) rig2.shadow.visible = false;
        if (rig2.outline) rig2.outline.visible = false;
        if (rig2.halo) rig2.halo.visible = false;
        if (rig2.fxA) rig2.fxA.visible = false;
        if (rig2.fxB) rig2.fxB.visible = false;
        return;
      }
      const size = rig2.size;
      const base = size / rig2.entry.px;
      const x = rig2.x + (pose.dx + sing.dx) * size;
      const y = rig2.y + (pose.dy + sing.dy) * size;
      const rotation = rig2.rotation + pose.rotation + sing.rotation;
      const sx = base * pose.scaleX * sing.scale * sing.scaleX;
      const sy = base * pose.scaleY * sing.scale * sing.scaleY;
      const scrambled = pose.scramble >= 0 && atlas.scramble.length > 0 ? atlas.scramble[pose.scramble % atlas.scramble.length] : null;
      const entry = scrambled ?? rig2.entry;
      const scrambleScale = scrambled ? rig2.entry.px / scrambled.px : 1;
      let tint = mixColor2(rig2.tint, rig2.sungTint, sing.color);
      tint = mixColor2(tint, rig2.flashTint, sing.flash);
      if (pose.backside) tint = rig2.backTint;
      rig2.main.tint = tint;
      setTexture(rig2.main, entry.fill);
      const splitting = pose.split > 1e-3 && rig2.fxA !== null && rig2.entry.halves !== null;
      place(rig2.main, x, y, rotation, sx * scrambleScale, sy * scrambleScale, pose.skew, splitting ? 0 : pose.alpha);
      const attach = splitting ? 1 - clamp019(pose.split * 3) : 1;
      if (rig2.outline) {
        setTexture(rig2.outline, entry.fat ?? entry.fill);
        place(rig2.outline, x, y, rotation, sx * scrambleScale, sy * scrambleScale, pose.skew, pose.alpha * attach);
      }
      if (rig2.shadow) {
        const lagged = evaluate(rig2, time, SHADOW_LAG, scratchShadow, null) ? scratchShadow : pose;
        const lx = rig2.x + (lagged.dx + sing.dx) * size + SHADOW_OFFSET_X * size;
        const ly = rig2.y + (lagged.dy + sing.dy) * size + SHADOW_OFFSET_Y * size;
        setTexture(rig2.shadow, entry.fat ?? entry.fill);
        place(
          rig2.shadow,
          lx,
          ly,
          rig2.rotation + lagged.rotation + sing.rotation,
          base * lagged.scaleX * sing.scale * sing.scaleX * scrambleScale,
          base * lagged.scaleY * sing.scale * sing.scaleY * scrambleScale,
          lagged.skew,
          Math.min(pose.alpha, lagged.alpha) * attach
        );
      }
      if (rig2.halo) {
        const k = 1 + 0.14 * sing.glow;
        place(rig2.halo, x, y, rotation, sx * k, sy * k, 0, pose.alpha * sing.glow * 0.95);
      }
      if (rig2.fxA && rig2.fxB) {
        if (splitting) {
          setFxMode(rig2, "split");
          const sep = pose.split;
          const c = Math.cos(rotation), s = Math.sin(rotation);
          const [ax, ay] = halvesKind === "lr" ? [-1.3 * sep, -0.45 * sep] : [-0.45 * sep, -1.3 * sep];
          place(rig2.fxA, x + (ax * c - ay * s) * size, y + (ax * s + ay * c) * size, rotation, sx, sy, pose.skew, pose.alpha);
          place(rig2.fxB, x - (ax * c - ay * s) * size, y - (ax * s + ay * c) * size, rotation, sx, sy, pose.skew, pose.alpha);
        } else if (pose.rgbSplit > 1e-3) {
          setFxMode(rig2, "rgb");
          setTexture(rig2.fxA, entry.fill);
          setTexture(rig2.fxB, entry.fill);
          const d = pose.rgbSplit * size;
          place(rig2.fxA, x - d, y, rotation, sx * scrambleScale, sy * scrambleScale, pose.skew, pose.alpha * 0.9);
          place(rig2.fxB, x + d, y + d * 0.2, rotation, sx * scrambleScale, sy * scrambleScale, pose.skew, pose.alpha * 0.9);
        } else if (pose.blur > 0.01) {
          setFxMode(rig2, "ghost");
          setTexture(rig2.fxA, entry.fill);
          setTexture(rig2.fxB, entry.fill);
          rig2.fxA.tint = tint;
          rig2.fxB.tint = tint;
          const k1 = 1 + 0.16 * pose.blur, k2 = 1 + 0.38 * pose.blur;
          place(rig2.fxA, x, y, rotation, sx * k1, sy * k1, pose.skew, pose.alpha * 0.4 * pose.blur);
          place(rig2.fxB, x, y, rotation, sx * k2, sy * k2, pose.skew, pose.alpha * 0.22 * pose.blur);
        } else {
          rig2.fxA.visible = false;
          rig2.fxB.visible = false;
        }
      }
    });
    if (wipeMask) {
      const active = time >= firstStart && time < lastLanded;
      if (active) {
        wipeMask.clear();
        rigs.forEach((rig2) => {
          if (!rig2.visible) return;
          const pose = rig2.pose;
          const size = rig2.size;
          const glyph = glyphs[rig2.index];
          const tx = Math.cos(rig2.angle), ty = Math.sin(rig2.angle);
          const nx = -ty, ny = tx;
          const margin = size * 0.2;
          const along = glyph.advance + margin * 2;
          const t0 = -along / 2;
          const t1 = t0 + along * pose.reveal;
          if (t1 <= t0) return;
          const n0 = -size * 0.85, n1 = size * 0.85;
          const cx = rig2.x + pose.dx * size, cy = rig2.y + pose.dy * size;
          wipeMask.poly([
            cx + tx * t0 + nx * n0,
            cy + ty * t0 + ny * n0,
            cx + tx * t1 + nx * n0,
            cy + ty * t1 + ny * n0,
            cx + tx * t1 + nx * n1,
            cy + ty * t1 + ny * n1,
            cx + tx * t0 + nx * n1,
            cy + ty * t0 + ny * n1
          ]).fill({ color: 16777215 });
        });
        if (masked.mask !== wipeMask) masked.mask = wipeMask;
        wipeMask.visible = true;
      } else if (masked.mask) {
        masked.mask = null;
        wipeMask.clear();
        wipeMask.visible = false;
      }
    }
    if (cursor) {
      let current = null;
      for (const rig2 of rigs) {
        if (time >= rig2.enterStart && (!current || rig2.enterStart >= current.enterStart)) current = rig2;
      }
      const first = rigs[0];
      const typing = time < lastLanded;
      const visibleFrom = options.enterAt - 0.25;
      const exitFrom = rigs.reduce((min, rig2) => Math.min(min, rig2.exitStart), Number.POSITIVE_INFINITY);
      const hideAt = Math.min(lastLanded + 1.2, exitFrom);
      const blinkOn = typing || Math.floor((time - lastLanded) / 0.28) % 2 === 0;
      const target = current ?? first ?? null;
      if (!target || time < visibleFrom || time >= hideAt || !blinkOn) {
        cursor.visible = false;
      } else {
        const glyph = glyphs[target.index];
        const tx = Math.cos(target.angle), ty = Math.sin(target.angle);
        const side = current ? 1 : -1;
        const offset = (glyph.advance / 2 + target.size * 0.1) * side;
        cursor.visible = true;
        cursor.position.set(target.x + tx * offset, target.y + ty * offset);
        cursor.rotation = target.angle;
        cursor.scale.set(Math.max(2, target.size * 0.09), target.size * 0.95);
        cursor.alpha = 1;
      }
    }
    underlines.forEach((line3) => {
      const landed = line3.members.every((rig2) => time >= rig2.landed);
      const grow = clamp019((time - line3.from) / Math.max(0.12, line3.to - line3.from));
      const retract = clamp019((time - line3.to - 0.12) / 0.28);
      const head = 1 - (1 - grow) ** 3;
      const tail = retract ** 3;
      const alpha = line3.members.reduce((min, rig2) => Math.min(min, rig2.visible ? rig2.pose.alpha : 0), 1);
      if (!landed || time < line3.from || head <= tail || alpha <= 2e-3) {
        line3.g.visible = false;
        return;
      }
      const tx = Math.cos(line3.angle), ty = Math.sin(line3.angle);
      line3.g.visible = true;
      line3.g.position.set(line3.x + tx * line3.length * tail, line3.y + ty * line3.length * tail);
      line3.g.rotation = line3.angle;
      line3.g.scale.set(line3.length * (head - tail), line3.thick * (1 + 0.5 * (1 - clamp019((time - line3.from) / 0.12))));
      line3.g.alpha = alpha;
    });
  };
  let anchorsAt = Number.NaN;
  let anchorsCache = [];
  const anchors = (time) => {
    if (time === anchorsAt) return anchorsCache;
    evaluateAll(time);
    anchorsAt = time;
    anchorsCache = glyphs.map((glyph, index) => {
      const rig2 = rigOf.get(index);
      const timing = timeline[index];
      if (!rig2) {
        return {
          char: glyph.char,
          x: glyph.x + shake.x,
          y: glyph.y + shake.y,
          size: glyph.size,
          sungAt: timing.startTime,
          sungEnd: timing.endTime,
          landedAt: Number.isFinite(enter.landed[index]) ? enter.landed[index] : options.enterAt,
          alpha: 0,
          blank: true
        };
      }
      const pose = rig2.pose;
      const sing = rig2.sing;
      const scale = (Math.abs(pose.scaleX * sing.scaleX) + Math.abs(pose.scaleY * sing.scaleY)) / 2 * sing.scale;
      return {
        char: glyph.char,
        x: rig2.x + (pose.dx + sing.dx) * rig2.size + shake.x,
        y: rig2.y + (pose.dy + sing.dy) * rig2.size + shake.y,
        size: rig2.size * scale,
        sungAt: rig2.sungAt,
        sungEnd: rig2.sungEnd,
        landedAt: rig2.landed,
        alpha: rig2.visible ? clamp019(pose.alpha) : 0,
        blank: false
      };
    });
    return anchorsCache;
  };
  let destroyed = false;
  return {
    view,
    blocks: blocksRoot,
    glyphs: glyphsRoot,
    update,
    prepare: () => atlas.paint?.() ?? false,
    anchors,
    bounds: { ...placement.bounds },
    destroy: () => {
      if (destroyed) return;
      destroyed = true;
      if (masked.mask) masked.mask = null;
      blocks.destroy();
      blocksRoot.destroy({ children: true, context: true });
      glyphsRoot.destroy({ children: true, context: true });
      view.destroy({ children: true });
      atlas.destroy();
    }
  };
};
var createHanabiText = (options) => buildHanabiText(options);

// folia:src/components/visualizer/hanabi/credits.ts
var smooth8 = (value) => {
  const t = Math.min(1, Math.max(0, value));
  return t * t * (3 - 2 * t);
};
var BLOOM_AT = 1.1;
var TITLE_START2 = 1.45;
var TITLE_STEP2 = 0.12;
var TITLE_SPAN2 = 2;
var clean2 = (value) => value?.trim() ?? "";
var hasHanabiCredits = (metadata) => Boolean(clean2(metadata.title) || clean2(metadata.artist) || clean2(metadata.album));
var resolveHanabiCreditsFrame = (time, finalEndTime) => {
  const elapsed = time - finalEndTime;
  if (elapsed <= 0) return { active: false, lyricAlpha: 1, lyricBlur: 0, posterAlpha: 0, posterOffsetY: 0, posterScale: 1 };
  const exit = smooth8(elapsed / 1.2);
  return {
    active: true,
    lyricAlpha: 1 - exit,
    lyricBlur: exit * 6,
    posterAlpha: smooth8((elapsed - 0.3) / 0.8),
    posterOffsetY: 0,
    posterScale: 1
  };
};
var titleLine2 = (title) => {
  const chars = Array.from(title);
  const step = Math.min(TITLE_STEP2, TITLE_SPAN2 / Math.max(chars.length, 1));
  return {
    fullText: title,
    startTime: TITLE_START2,
    endTime: TITLE_START2 + step * chars.length + 0.4,
    words: chars.map((text, i) => ({ text, startTime: TITLE_START2 + i * step, endTime: TITLE_START2 + (i + 1) * step }))
  };
};
var TITLE_SPEC = {
  layout: "center",
  heroSize: 0.11,
  emphasis: 0.2,
  tilt: 0,
  block: "band",
  enter: "pop",
  sing: "color",
  exit: "ascend",
  stagger: 0.05,
  outline: false,
  hardShadow: true
};
var createHanabiCredits = (pixi, options) => {
  const { width, height, theme, tuning } = options;
  const palette = resolveHanabiPalette("kawaii", theme, tuning.colorMode);
  const title = clean2(options.metadata.title);
  const artist = clean2(options.metadata.artist);
  const album = clean2(options.metadata.album);
  const view = new pixi.Container();
  const sky = new pixi.Container();
  view.addChild(sky);
  const fireworks = createFireworks(pixi, options.textures, {
    width,
    height,
    palette,
    amount: Math.max(0, tuning.sparkAmount),
    maxParticles: 1400
  });
  sky.addChild(fireworks.view);
  const glow = tuning.glow > 0 ? createHanabiGlow(pixi, Math.min(2, tuning.glow), resolveHanabiGlowQuality(width, height, options.resolution, tuning.renderQuality)) : null;
  if (glow) sky.filters = [glow];
  const bursts = [
    { x: width * 0.5, y: height * 0.34, at: BLOOM_AT, spec: { ...burstPreset("kamuro", [0, 1, 3]), count: 150, radius: 0.46, duration: 4.2 }, seed: "hanabi:credits:crown", scale: 1 },
    { x: width * 0.2, y: height * 0.3, at: BLOOM_AT + 0.55, spec: burstPreset("senrin", [1, 2, 3]), seed: "hanabi:credits:left", scale: 0.8 },
    { x: width * 0.8, y: height * 0.27, at: BLOOM_AT + 0.8, spec: burstPreset("senrin", [2, 3, 0]), seed: "hanabi:credits:right", scale: 0.8 },
    { x: width * 0.5, y: height * 0.22, at: BLOOM_AT + 2.2, spec: burstPreset("willow-ring", [3, 0, 1]), seed: "hanabi:credits:finale", scale: 0.9 }
  ];
  const launches = bursts.map((burst2, k) => ({
    fromX: burst2.x + (k % 2 === 0 ? -1 : 1) * width * 0.02,
    fromY: height * 1.03,
    toX: burst2.x,
    toY: burst2.y,
    at: burst2.at - 0.45,
    duration: 0.45,
    color: palette.glow,
    seed: `hanabi:credits:launch${k}`
  }));
  const text = title ? createHanabiText({
    pixi,
    width,
    height,
    resolution: options.resolution,
    theme,
    line: titleLine2(title),
    regionWidth: width * 0.72,
    regionHeight: height * 0.26,
    spec: { ...TITLE_SPEC, heroSize: TITLE_SPEC.heroSize * (options.fontScale ?? 1) },
    palette,
    seed: "hanabi:credits:title",
    enterAt: BLOOM_AT - 0.1,
    // 片尾卡一直停在最后一帧，字不退场。
    exitAt: 1e6,
    exitDuration: 1,
    motion: Math.max(0, tuning.textMotion),
    blockOpacity: Math.min(1, Math.max(0, tuning.blockOpacity))
  }) : null;
  if (text) {
    text.view.position.set(width / 2, height * 0.5);
    view.addChild(text.view);
  }
  const font = resolveThemeFontStack(theme);
  const detailSize = Math.max(13, height * 0.03);
  const detailStyle = (size, spacing) => new pixi.TextStyle({
    fontFamily: font,
    fontWeight: String(resolveThemeFontWeight(theme, 600)),
    fontSize: size,
    fill: palette.paper,
    letterSpacing: size * spacing,
    align: "center",
    wordWrap: true,
    wordWrapWidth: width * 0.7
  });
  const titleDone = TITLE_START2 + Math.min(TITLE_SPAN2, TITLE_STEP2 * Array.from(title).length);
  const details = [
    artist ? { text: artist.toLocaleUpperCase(), y: 0.66, size: detailSize, spacing: 0.3, delay: title ? titleDone : 1.2 } : null,
    album ? { text: album, y: 0.35, size: detailSize * 0.8, spacing: 0.16, delay: (title ? titleDone : 1.2) + 0.3 } : null
  ].filter((item) => item !== null).map((item) => {
    const label = new pixi.Text({ text: item.text, style: detailStyle(item.size, item.spacing), resolution: options.resolution });
    label.anchor.set(0.5);
    label.position.set(width / 2, item.y * height);
    label.alpha = 0;
    view.addChild(label);
    return { label, delay: item.delay, y: item.y * height };
  });
  const collageCache = tuning.collage > 0 && !tuning.textOnly ? createCollageTextureCache(pixi, options.resolution, font) : null;
  let collage = null;
  if (collageCache) {
    const unit = Math.min(width, height);
    const stay = { exitAt: 1e6, exitDuration: 1 };
    const band2 = (style, y, rotation, color, at, from) => ({
      kind: "strip",
      style,
      x: width / 2,
      y,
      length: Math.hypot(width, height) * 1.25,
      thickness: Math.max(18, unit * (style === "film" ? 0.075 : 0.06)),
      rotation,
      color,
      speed: from * unit * (style === "film" ? 0.12 : 0.05),
      from,
      at,
      ...stay
    });
    const items = [
      band2("film", height * 0.85, 0.06, CANDY[0], TITLE_START2 + 0.4, -1),
      band2("lace", height * 0.13, -0.05, CANDY[3], TITLE_START2 + 0.7, 1),
      {
        kind: "pop",
        x: width * 0.72,
        y: height * 0.22,
        icon: options.icons?.[0] ?? HANABI_FALLBACK_ICON,
        color: ICON_INKS[0],
        size: unit * 0.12,
        rotation: 0.16,
        at: BLOOM_AT + 0.04,
        duration: 1.4
      }
    ];
    const shapes = ["heart", "star", "ribbon", "sparkle"];
    shapes.forEach((shape, k) => {
      items.push({
        kind: "sticker",
        shape,
        label: null,
        layer: "front",
        x: width / 2 + (k === 0 || k === 3 ? -1 : 1) * Math.min(width * 0.38, unit * 0.62),
        y: height * 0.5 + (k < 2 ? -1 : 1) * unit * 0.1,
        size: unit * 0.08,
        rotation: (k % 2 === 0 ? -1 : 1) * 0.25,
        color: CANDY[(k + 3) % CANDY.length],
        at: TITLE_START2 + 0.5 + k * 0.12,
        ...stay
      });
    });
    for (let k = 0; k < 6; k += 1) {
      items.push({
        kind: "floater",
        shape: shapes[k % shapes.length],
        x: width * (0.12 + k * 0.37 % 1 * 0.76),
        y: height * 1.08,
        rise: height * 1.3,
        size: unit * (0.05 + k % 3 * 0.012),
        color: CANDY[k % CANDY.length],
        at: 2.4 + k * 0.9,
        duration: 4.2,
        sway: unit * 0.03
      });
    }
    collage = createShotCollage(pixi, { recipe: null, items }, collageCache, options.textures);
    view.addChildAt(collage.back, view.getChildIndex(sky) + 1);
    view.addChild(collage.front);
  }
  const update = (elapsed) => {
    const time = Math.max(0, elapsed);
    fireworks.update(time, bursts, launches);
    text?.update(time);
    collage?.update(time < 8 ? time : 2.4 + (time - 2.4) % 5.6);
    details.forEach(({ label, delay, y }) => {
      const k = smooth8((time - delay) / 0.9);
      label.alpha = k * 0.92;
      label.position.y = y + (1 - k) * height * 0.02;
    });
  };
  update(0);
  return {
    view,
    update,
    destroy: () => {
      sky.filters = [];
      glow?.destroy();
      fireworks.destroy();
      text?.destroy();
      collage?.destroy();
      view.destroy({ children: true });
      collageCache?.destroy();
    }
  };
};

// folia:src/components/visualizer/hanabi/hanabiCreditsLayer.ts
var PREBUILD_SECONDS2 = 4;
var INACTIVE2 = { active: false, lyricAlpha: 1, lyricBlur: 0, posterAlpha: 0, posterOffsetY: 0, posterScale: 1 };
var toSongMetadata2 = (metadata) => ({
  title: metadata.title ?? null,
  artist: metadata.artist ?? null,
  album: metadata.album ?? null
});
var HanabiCreditsLayer = class {
  constructor(pixi) {
    this.pixi = pixi;
    this.holder = new pixi.Container();
    this.holder.visible = false;
  }
  holder;
  credits = null;
  lyricEndTime = 0;
  get built() {
    return this.credits !== null;
  }
  hasMetadata(metadata) {
    return hasHanabiCredits(toSongMetadata2(metadata));
  }
  /** 片尾时间线帧；没有片尾卡时恒为 inactive（歌词不淡出）。 */
  resolveFrame(time, program, metadata) {
    if (program.lyricEndTime === null || !this.hasMetadata(metadata)) return INACTIVE2;
    this.lyricEndTime = program.lyricEndTime;
    return resolveHanabiCreditsFrame(time, program.lyricEndTime);
  }
  needsBuild(time, program, metadata) {
    return !this.credits && program.lyricEndTime !== null && time >= program.lyricEndTime - PREBUILD_SECONDS2 && this.hasMetadata(metadata);
  }
  build(context) {
    this.invalidate();
    this.credits = createHanabiCredits(this.pixi, {
      width: context.width,
      height: context.height,
      resolution: context.resolution,
      theme: context.theme,
      metadata: toSongMetadata2(context.metadata),
      tuning: context.tuning,
      textures: context.textures,
      icons: context.icons
    });
    this.holder.addChild(this.credits.view);
    this.holder.pivot.set(context.width / 2, context.height / 2);
  }
  /** 片尾卡以画面中心缩放、上下偏移；没激活时整层不画。 */
  update(time, frame2, width, height) {
    const credits = this.credits;
    this.holder.visible = Boolean(credits) && frame2.active && frame2.posterAlpha > 2e-3;
    if (!credits || !this.holder.visible) return;
    this.holder.alpha = frame2.posterAlpha;
    this.holder.position.set(width / 2, height / 2 + frame2.posterOffsetY * height);
    this.holder.scale.set(frame2.posterScale);
    credits.update(time - this.lyricEndTime);
  }
  /** 作废当前片尾卡（下次需要时重建）。 */
  invalidate() {
    if (!this.credits) return;
    const credits = this.credits;
    this.credits = null;
    this.holder.removeChild(credits.view);
    credits.destroy();
    this.holder.visible = false;
  }
  destroy() {
    this.invalidate();
    this.holder.destroy({ children: true });
  }
};

// folia:src/components/visualizer/hanabi/hanabiScreenBloom.ts
var CHORUS_MERGE_GAP = 1.5;
var RAMP_IN_BEFORE = 0.5;
var RAMP_IN_AFTER = 0.3;
var RAMP_OUT_BEFORE = 0.2;
var RAMP_OUT_AFTER = 0.9;
var resolveHanabiChorusSpans = (lines) => {
  const spans = [];
  lines.forEach((line2, index) => {
    if (!line2.isChorus) return;
    const next = lines[index + 1];
    const endTime = next ? Math.max(line2.startTime, next.startTime) : getLineRenderEndTime(line2);
    const last = spans.at(-1);
    if (last && line2.startTime - last.endTime < CHORUS_MERGE_GAP) last.endTime = Math.max(last.endTime, endTime);
    else spans.push({ startTime: line2.startTime, endTime });
  });
  return spans;
};
var smooth9 = (value) => {
  const t = Math.min(1, Math.max(0, value));
  return t * t * (3 - 2 * t);
};
var resolveHanabiChorusWeight = (spans, time) => {
  let weight = 0;
  for (const span of spans) {
    if (time < span.startTime - RAMP_IN_BEFORE) break;
    if (time > span.endTime + RAMP_OUT_AFTER) continue;
    const rampIn = smooth9((time - (span.startTime - RAMP_IN_BEFORE)) / (RAMP_IN_BEFORE + RAMP_IN_AFTER));
    const rampOut = 1 - smooth9((time - (span.endTime - RAMP_OUT_BEFORE)) / (RAMP_OUT_BEFORE + RAMP_OUT_AFTER));
    weight = Math.max(weight, Math.min(rampIn, rampOut));
  }
  return weight;
};
var HANABI_SCREEN_BLOOM = {
  base: 0.45,
  chorus: 0.9
};
var resolveHanabiScreenBloomStrength = (bloom2, chorusBloom, chorusWeight) => Math.max(0, bloom2) * HANABI_SCREEN_BLOOM.base + Math.max(0, chorusBloom) * HANABI_SCREEN_BLOOM.chorus * chorusWeight;

// folia:src/components/visualizer/hanabi/timeline.ts
var RISE_BEFORE = 0.6;
var RISE_AFTER = 0.6;
var LAUNCH_DURATION = 0.45;
var ENTER_LEAD = 0.4;
var DRIFT_PER_SECOND = 0.03;
var DRIFT_MAX = 0.15;
var SWING_SHARPNESS = 4;
var PUNCH_ATTACK = 0.05;
var SPIN_CRUISE = 0.2;
var SPIN_CRUISE_TOTAL = 0.85;
var SPIN_SWING_MIN = 0.6;
var SPIN_SWING_RANGE = 0.8;
var SPIN_FLIP = 0.2;
var clamp4 = (value, min, max) => Math.min(max, Math.max(min, value));
var smooth10 = (value) => {
  const t = clamp4(value, 0, 1);
  return t * t * (3 - 2 * t);
};
var easeSeptic = (value) => {
  const t = clamp4(value, 0, 1);
  return t ** 4 * (35 + t * (-84 + t * (70 - 20 * t)));
};
var easeSepticIntegral = (t) => t ** 5 * (7 + t * (-14 + t * (10 - 2.5 * t)));
var binomial = (n, k) => {
  let result = 1;
  for (let i = 1; i <= k; i += 1) result = result * (n - k + i) / i;
  return result;
};
var SWING_TERMS = Array.from({ length: SWING_SHARPNESS + 1 }, (_, k) => binomial(SWING_SHARPNESS, k) * (-1) ** k / (2 * k + 1));
var swingPrimitive = (u) => {
  const u2 = u * u;
  let power = u;
  let sum = 0;
  for (const term of SWING_TERMS) {
    sum += term * power;
    power *= u2;
  }
  return sum;
};
var SWING_HALF = swingPrimitive(1);
var easeSwing = (value) => 0.5 + swingPrimitive(2 * clamp4(value, 0, 1) - 1) / (2 * SWING_HALF);
var planSpin = (durations, options) => {
  const angles = [];
  const drift = [];
  let direction = options.direction;
  durations.forEach((duration, index) => {
    if (index > 0) {
      const last = index === durations.length - 1;
      const roll = options.random();
      const reversed = direction !== options.direction;
      if (reversed ? last || roll < 0.5 : !last && roll < SPIN_FLIP) direction = -direction;
    }
    const cruise = direction * options.amount * Math.min(SPIN_CRUISE, SPIN_CRUISE_TOTAL / Math.max(duration, 0.5));
    drift.push(cruise);
    if (index === 0) {
      angles.push(0);
      return;
    }
    const swing = direction * options.amount * (SPIN_SWING_MIN + SPIN_SWING_RANGE * options.random());
    angles.push(angles[index - 1] + (drift[index - 1] * durations[index - 1] + cruise * duration) / 2 + swing);
  });
  return { angles, drift };
};
var buildTimeline = (shots, options) => {
  const { height, riseSpeed, motion } = options;
  const count = shots.length;
  const durationOf = (index) => Math.max(shots[index].endTime - shots[index].startTime, 0.05);
  const before = shots.map((_, index) => index === 0 ? 0 : Math.min(RISE_BEFORE, 0.45 * durationOf(index - 1)));
  const after = shots.map((_, index) => index === 0 ? 0 : Math.min(RISE_AFTER, 0.35 * durationOf(index)));
  const timings = [];
  let worldY = 0;
  shots.forEach((shot, index) => {
    if (index > 0) worldY -= clamp4(shot.camera.rise, 0, 1.2) * riseSpeed * height;
    const boundary = shot.startTime;
    const sung = shot.firstSung ?? boundary;
    let enterAt = shot.isBridge ? boundary : Math.min(boundary, sung) - ENTER_LEAD;
    if (index > 0) enterAt = Math.max(enterAt, boundary - before[index], timings[index - 1].enterAt + 0.1);
    const duration = durationOf(index);
    timings.push({
      start: shot.startTime,
      end: shot.endTime,
      worldY,
      launchAt: enterAt - LAUNCH_DURATION,
      enterAt,
      exitAt: 0,
      exitDuration: 0,
      punchAt: enterAt + 0.08,
      riseIn: index === 0 ? null : { from: boundary - before[index], to: boundary + after[index] },
      drift: riseSpeed * height * Math.min(DRIFT_PER_SECOND, DRIFT_MAX / duration),
      spin: options.spinAngles?.[index] ?? 0,
      spinDrift: options.spinDrift?.[index] ?? 0
    });
  });
  timings.forEach((timing, index) => {
    const shot = shots[index];
    const sungEnd = shot.lastSungEnd ?? timing.end;
    let exitAt;
    let exitDuration;
    if (index < count - 1) {
      const boundary = timing.end;
      exitAt = clamp4(sungEnd, boundary - before[index + 1], boundary - 0.15);
      exitDuration = clamp4(boundary + after[index + 1] - exitAt, 0.35, 0.9);
    } else if (options.exitStart != null) {
      exitAt = Math.min(Math.max(sungEnd, options.exitStart), options.unitEnd - 0.2);
      exitDuration = clamp4(options.unitEnd - exitAt, 0.25, 0.7);
    } else {
      exitAt = options.unitEnd;
      exitDuration = 0.5;
    }
    timing.exitAt = Math.max(exitAt, timing.enterAt + 0.3);
    timing.exitDuration = exitDuration;
  });
  const shotAt = (time) => {
    let found = 0;
    for (let index = 0; index < count; index += 1) if (timings[index].start <= time) found = index;
    return found;
  };
  const blended = (time, value) => {
    for (let index = 1; index < count; index += 1) {
      const window2 = timings[index].riseIn;
      if (time >= window2.from && time <= window2.to) {
        const k = easeSwing((time - window2.from) / Math.max(window2.to - window2.from, 1e-3));
        return value(index - 1, time) + (value(index, time) - value(index - 1, time)) * k;
      }
    }
    return value(shotAt(time), time);
  };
  const target = (index, time) => {
    const timing = timings[index];
    return -timing.worldY + timing.drift * (time - (timing.start + timing.end) / 2);
  };
  const rise = (time) => count === 0 ? 0 : blended(time, target);
  const mids = timings.map((timing) => (timing.start + timing.end) / 2);
  const spinSteps = timings.map((timing, index) => {
    if (index === 0) return null;
    const previous = timings[index - 1];
    const window2 = timing.riseIn;
    const ramp = Math.max(window2.to - window2.from, 1e-3);
    const from = mids[index - 1];
    const drift = (time) => {
      const x = (time - window2.from) / ramp;
      const switched = x <= 0 ? 0 : x >= 1 ? ramp / 2 + (time - window2.to) : ramp * easeSepticIntegral(x);
      return previous.spinDrift * (time - from) + (timing.spinDrift - previous.spinDrift) * switched;
    };
    const swing = timing.spin - previous.spin - drift(mids[index]);
    return (time) => previous.spin + drift(time) + swing * easeSwing((time - window2.from) / ramp);
  });
  const spin = (time) => {
    if (count === 0) return 0;
    if (time <= mids[0]) return timings[0].spin + timings[0].spinDrift * (time - mids[0]);
    for (let index = 1; index < count; index += 1) {
      if (time < mids[index]) return spinSteps[index](time);
    }
    const last = timings[count - 1];
    return last.spin + last.spinDrift * (time - mids[count - 1]);
  };
  const pushOf = (index, time) => {
    const timing = timings[index];
    return 1 + shots[index].camera.push * smooth10((time - timing.start) / Math.max(timing.end - timing.start, 0.05));
  };
  const rollOf = (index, time) => {
    const timing = timings[index];
    return shots[index].camera.roll * motion * Math.sin((time - timing.start) * 0.9 + index * 1.3);
  };
  const camera = (time) => {
    if (count === 0) return { scale: 1, rotation: 0, dx: 0, dy: 0 };
    let scale = blended(time, pushOf);
    const rotation = blended(time, rollOf);
    let dx = 0;
    let dy = 0;
    for (let index = 0; index < count; index += 1) {
      const age = time - timings[index].punchAt;
      const punch = shots[index].camera.punch;
      if (age < 0 || age > 0.9 || punch <= 0 || shots[index].isBridge) continue;
      const amp = punch * motion * Math.exp(-age / 0.16) * smooth10(age / PUNCH_ATTACK);
      dx += amp * 0.012 * height * Math.sin(age * 70 + index);
      dy += amp * 0.016 * height * Math.cos(age * 55 + index * 2);
      scale *= 1 + amp * 0.03;
    }
    return { scale, rotation, dx, dy };
  };
  return { shots: timings, rise, spin, shotAt, camera };
};

// folia:src/components/visualizer/hanabi/hanabiTransitions.ts
var HANABI_TRANSITION_KINDS = ["ascend", "flash", "bloom"];
var ease = easeSeptic;
var launch = (p) => p <= 0 ? 0 : p >= 1 ? 1 + 2 * (p - 1) : p * p * p * (2 - p);
var frame = (partial) => ({ alpha: 1, scale: 1, blur: 0, y: 0, rotation: 0, ...partial });
var resolveFrame = (kind, phase, progress) => {
  const p = Math.max(0, phase === "exit" ? progress : Math.min(1, progress));
  if (kind === "ascend") {
    if (phase === "exit") {
      const e = launch(p);
      return frame({ y: 0.32 * e, blur: 10 * Math.min(e, 1), alpha: 1 - 0.7 * ease((p - 0.5) / 0.5), rotation: 0.55 * e });
    }
    const k2 = launch(1 - p);
    return frame({ y: -0.26 * k2, blur: 10 * k2, alpha: 1 - 0.7 * k2, rotation: -0.5 * k2 });
  }
  if (kind === "flash") {
    const near = phase === "exit" ? ease(p) : 1 - ease(p);
    return frame({ scale: 1 + 0.05 * near, blur: 9 * near * near, alpha: 1 - 0.55 * near * near, rotation: (phase === "exit" ? 0.12 : -0.12) * near });
  }
  if (phase === "exit") {
    const e = ease(p);
    return frame({ scale: 1 + 0.18 * e, blur: 5 * e, alpha: 1 - e, rotation: 0.3 * e });
  }
  const k = 1 - ease(p);
  return frame({ scale: 1 - 0.08 * k, blur: 4 * k, alpha: 1 - k, rotation: -0.25 * k });
};
var HANABI_TRANSITIONS = Object.fromEntries(
  HANABI_TRANSITION_KINDS.map((kind) => [kind, {
    kind,
    duration: (gap) => kind === "flash" ? Math.min(0.5, Math.max(0.28, gap > 0 ? gap * 0.4 : 0.35)) : Math.min(1.1, Math.max(0.5, gap > 0 ? gap * 0.6 : 0.8)),
    enterClamp: kind === "flash" ? [0.2, 0.45] : [0.4, 0.9],
    resolveFrame: (phase, progress) => resolveFrame(kind, phase, progress)
  }])
);
var resolveHanabiEnterDuration = (kind, startTime, endTime) => {
  const [min, max] = HANABI_TRANSITIONS[kind].enterClamp;
  return Math.max(min, Math.min(max, endTime - startTime));
};
var chooseHanabiTransition = (seed, paragraphIndex, previous) => {
  let hash = 0;
  for (const char of `${seed}:${paragraphIndex}:hanabi-transition`) hash = hash * 31 + char.charCodeAt(0) | 0;
  const roll = Math.abs(hash);
  if (previous !== "ascend" && roll % 2 === 0) return "ascend";
  const choices = HANABI_TRANSITION_KINDS.filter((kind) => kind !== previous && kind !== "ascend");
  return choices[(roll >> 1) % choices.length];
};

// folia:src/components/visualizer/hanabi/program.ts
var DEFAULT_HANABI_PARAMS = {
  bridgeGap: 3,
  maxChars: 18,
  maxLineSeconds: 6
};
var RECENT2 = 6;
var BRIDGE_FAMILIES2 = ["senrin", "uchiage", "kiku", "shakudama"];
var BRIDGE_TAIL = 0.6;
var MAX_PIECES = 3;
var MOODS_BY_KIND2 = {
  chorus: ["loud", "neutral"],
  lift: ["loud", "neutral"],
  verse: ["neutral", "quiet"],
  breath: ["quiet", "neutral"],
  outro: ["quiet", "neutral"],
  break: null
};
var locateWords = (line2) => {
  const text = line2.fullText;
  const located = [];
  let cursor = 0;
  for (const word of line2.words ?? []) {
    if (!word.text) continue;
    const index = text.indexOf(word.text, cursor);
    if (index < 0) return null;
    located.push({ word, start: index, end: index + word.text.length });
    cursor = index + word.text.length;
  }
  return located.length > 0 ? located : null;
};
var hasLetters = (text) => /[\p{L}\p{N}]/u.test(text);
var segmentHanabiLine = (line2) => {
  const text = line2.fullText;
  const located = locateWords(line2);
  if (located && located.length >= 2) {
    return located.map(({ word, start, end }) => ({ startOffset: start, endOffset: end, startTime: word.startTime, endTime: word.endTime }));
  }
  const pieces = segmentLyricWords(line2).map(({ segment: segment2, index }) => ({ start: index, end: index + segment2.length, text: segment2 }));
  const merged = [];
  for (const piece of pieces) {
    const last = merged.at(-1);
    if (last && !hasLetters(piece.text)) last.end = piece.end;
    else merged.push({ start: piece.start, end: piece.end });
  }
  const length = Math.max(text.length, 1);
  const timeAt = (offset) => line2.startTime + (line2.endTime - line2.startTime) * (offset / length);
  return merged.map(({ start, end }) => ({ startOffset: start, endOffset: end, startTime: timeAt(start), endTime: timeAt(end) }));
};
var sliceLine = (line2, startOffset, endOffset) => {
  const text = line2.fullText;
  const start = Math.max(0, Math.min(startOffset, text.length));
  const end = Math.max(start, Math.min(endOffset, text.length));
  if (start === 0 && end === text.length) return line2;
  const located = locateWords(line2) ?? [{ word: { text, startTime: line2.startTime, endTime: line2.endTime }, start: 0, end: text.length }];
  const words = [];
  for (const { word, start: ws, end: we } of located) {
    const from = Math.max(ws, start);
    const to = Math.min(we, end);
    if (to <= from) continue;
    const span = Math.max(we - ws, 1);
    const duration = word.endTime - word.startTime;
    words.push({
      text: text.slice(from, to),
      startTime: word.startTime + duration * ((from - ws) / span),
      endTime: word.startTime + duration * ((to - ws) / span)
    });
  }
  const fullText = text.slice(start, end);
  if (words.length === 0) {
    const length = Math.max(text.length, 1);
    const timeAt = (offset) => line2.startTime + (line2.endTime - line2.startTime) * (offset / length);
    words.push({ text: fullText, startTime: timeAt(start), endTime: timeAt(end) });
  }
  return {
    ...line2,
    fullText,
    words,
    startTime: words[0].startTime,
    endTime: words.at(-1).endTime,
    translation: void 0,
    romanization: void 0
  };
};
var shotLine = (lines, slices) => {
  const parts = slices.map((slice) => {
    const line2 = lines.get(slice.lineIndex);
    return line2 ? sliceLine(line2, slice.startOffset, slice.endOffset) : null;
  }).filter((line2) => line2 !== null && line2.fullText.trim().length > 0);
  if (parts.length === 0) return null;
  if (parts.length === 1) return parts[0];
  const words = [];
  parts.forEach((part, index) => {
    if (index > 0) {
      const gapAt = words.at(-1).endTime;
      words.push({ text: " ", startTime: gapAt, endTime: Math.max(gapAt, part.startTime) });
    }
    words.push(...part.words);
  });
  return {
    ...parts[0],
    fullText: words.map((word) => word.text).join(""),
    words,
    startTime: parts[0].startTime,
    endTime: Math.max(...parts.map((part) => part.endTime))
  };
};
var visibleLength = (text) => splitLyricGraphemes(text).filter((grapheme) => grapheme.trim().length > 0).length;
var splitLine = (unified, params) => {
  const { line: line2 } = unified;
  const text = line2.fullText;
  const whole = [{
    slice: { lineIndex: unified.sourceIndex, startOffset: 0, endOffset: text.length },
    startTime: line2.startTime,
    lyricEndTime: unified.renderEndTime
  }];
  const count = visibleLength(text);
  const duration = line2.endTime - line2.startTime;
  const maxChars = Math.max(4, params.maxChars);
  const maxSeconds = Math.max(1, params.maxLineSeconds);
  if (count <= maxChars && duration <= maxSeconds) return whole;
  const segments = segmentHanabiLine(line2);
  const pieces = Math.min(MAX_PIECES, segments.length, Math.max(2, Math.ceil(Math.max(count / maxChars, duration / maxSeconds))));
  if (pieces < 2) return whole;
  const cuts = [];
  let after = -1;
  for (let k = 1; k < pieces; k += 1) {
    const target = text.length * k / pieces;
    let best = -1;
    for (let j = after + 1; j <= segments.length - 1 - (pieces - k); j += 1) {
      const offset = segments[j + 1].startOffset;
      if (best < 0 || Math.abs(offset - target) < Math.abs(segments[best + 1].startOffset - target)) best = j;
    }
    if (best < 0) break;
    cuts.push(best);
    after = best;
  }
  if (cuts.length === 0) return whole;
  const bounds = [-1, ...cuts, segments.length - 1];
  const result = [];
  for (let k = 0; k < bounds.length - 1; k += 1) {
    const first = segments[bounds[k] + 1];
    const last = segments[bounds[k + 1]];
    const isFirst = k === 0;
    const isLast = k === bounds.length - 2;
    result.push({
      slice: {
        lineIndex: unified.sourceIndex,
        startOffset: isFirst ? 0 : first.startOffset,
        endOffset: isLast ? text.length : segments[bounds[k + 1] + 1].startOffset
      },
      startTime: isFirst ? line2.startTime : first.startTime,
      lyricEndTime: isLast ? unified.renderEndTime : last.endTime
    });
  }
  return result;
};
var planShots2 = (lines, paragraphStart, paragraphEnd, params) => {
  const pieces = lines.flatMap((line2) => splitLine(line2, params).map((piece, index) => ({ ...piece, slot: `s${index}` })));
  const shots = [];
  let cursor = pieces.length > 0 ? Math.min(paragraphStart, pieces[0].startTime) : paragraphStart;
  pieces.forEach((piece, index) => {
    const start = cursor;
    const nextStart = Math.max(pieces[index + 1]?.startTime ?? paragraphEnd, start + 0.05);
    const lyricEnd = piece.lyricEndTime;
    if (index < pieces.length - 1 && nextStart - lyricEnd >= params.bridgeGap) {
      const end = Math.max(start + 0.05, lyricEnd + BRIDGE_TAIL);
      shots.push({ slices: [piece.slice], slot: piece.slot, startTime: start, endTime: end, lyricEndTime: lyricEnd, isBridge: false });
      shots.push({ slices: [], slot: null, startTime: end, endTime: nextStart, lyricEndTime: nextStart, isBridge: true });
    } else {
      const end = index < pieces.length - 1 ? nextStart : Math.max(nextStart, lyricEnd);
      shots.push({ slices: [piece.slice], slot: piece.slot, startTime: start, endTime: end, lyricEndTime: Math.min(lyricEnd, end), isBridge: false });
    }
    cursor = shots.at(-1).endTime;
  });
  if (pieces.length === 0 && paragraphEnd > paragraphStart) {
    shots.push({ slices: [], slot: null, startTime: paragraphStart, endTime: paragraphEnd, lyricEndTime: paragraphEnd, isBridge: true });
  }
  return shots;
};
var castShot2 = (options) => {
  const { chain } = options;
  let candidates = HANABI_KINDS;
  const narrow = (keep) => {
    const next = candidates.filter(keep);
    if (next.length > 0) candidates = next;
  };
  const moods = MOODS_BY_KIND2[options.kind];
  if (options.isBridge) narrow((kind) => BRIDGE_FAMILIES2.includes(profileOf2(kind).family));
  if (moods) narrow((kind) => moods.includes(profileOf2(kind).mood));
  narrow((kind) => !chain.recent.includes(kind));
  if (chain.family) narrow((kind) => profileOf2(kind).family !== chain.family);
  const random = createRng2(`${options.seed}:${options.paragraphIndex}:${options.shotIndex}:hanabi-cast`);
  return candidates[Math.floor(random() * candidates.length)];
};
var advanceChain2 = (chain, kind) => {
  chain.recent = [...chain.recent, kind].slice(-RECENT2);
  chain.family = profileOf2(kind).family;
};
var shotText = (shot) => {
  const text = profileOf2(shot.typography ?? shot.kind).text;
  const block = shot.block ?? text.block;
  const enter = shot.enter ?? text.enter;
  return block === text.block && enter === text.enter ? text : { ...text, block, enter };
};
var resolveShotProfile = (shot) => {
  const base = profileOf2(shot.kind);
  const text = shotText(shot);
  const burst2 = shot.burst && shot.burst !== base.burst?.kind ? burstPreset(shot.burst, base.burst?.colors) : base.burst;
  if (text === base.text && burst2 === base.burst) return base;
  return { ...base, text, burst: burst2 };
};

// folia:src/components/visualizer/hanabi/hanabiProgram.ts
var INSTRUMENTAL_DURATION2 = 480;
var INSTRUMENTAL_PARAGRAPH2 = 28;
var BRIDGE_SHOT2 = 7;
var BRIDGE_SPLIT2 = 10;
var BRIDGE_TAIL2 = 0.6;
var closeTail = (shots, endTime, params) => {
  const last = shots.at(-1);
  if (!last || last.isBridge || endTime - last.lyricEndTime < params.bridgeGap) return shots;
  const end = Math.max(last.startTime + 0.05, last.lyricEndTime + BRIDGE_TAIL2);
  return [
    ...shots.slice(0, -1),
    { ...last, endTime: end },
    { slices: [], slot: null, startTime: end, endTime, lyricEndTime: endTime, isBridge: true }
  ];
};
var splitLongBridges2 = (shots) => shots.flatMap((shot) => {
  const length = shot.endTime - shot.startTime;
  if (!shot.isBridge || length <= BRIDGE_SPLIT2) return [shot];
  const count = Math.max(2, Math.round(length / BRIDGE_SHOT2));
  return Array.from({ length: count }, (_, index) => {
    const startTime = shot.startTime + length * index / count;
    const endTime = index === count - 1 ? shot.endTime : shot.startTime + length * (index + 1) / count;
    return { slices: [], slot: null, startTime, endTime, lyricEndTime: endTime, isBridge: true };
  });
});
var planLyricParagraphs2 = (lines, params, duration) => {
  const structure = buildStructureLines(lines);
  const drafts = draftParagraphs(structure, resolveParagraphGapThreshold(lines));
  const lyricEndTime = Math.max(...structure.map((line2) => line2.renderEndTime));
  const programEnd = Math.max(lyricEndTime, duration ?? 0);
  const firstStart = structure[0].line.startTime;
  const plans = [];
  const intro = firstStart >= params.bridgeGap;
  if (intro) plans.push({ lines: [], kind: "break", startTime: 0, endTime: firstStart, lyricEndTime: firstStart });
  drafts.forEach((draft, index) => {
    const next = drafts[index + 1];
    plans.push({
      lines: draft.lines,
      kind: classifyParagraph(draft.lines, index, drafts.length),
      startTime: index === 0 && !intro ? Math.min(0, firstStart) : draft.lines[0].line.startTime,
      endTime: next ? next.lines[0].line.startTime : programEnd,
      lyricEndTime: draft.lines.at(-1).renderEndTime
    });
  });
  return { plans, lyricEndTime, programEnd };
};
var planInstrumentalParagraphs2 = (duration) => {
  const count = Math.max(1, Math.round(duration / INSTRUMENTAL_PARAGRAPH2));
  return Array.from({ length: count }, (_, index) => {
    const startTime = duration * index / count;
    const endTime = index === count - 1 ? duration : duration * (index + 1) / count;
    return { lines: [], kind: "break", startTime, endTime, lyricEndTime: endTime };
  });
};
var compileHanabiProgram = (lines, seed, params = {}, options = {}) => {
  const resolvedParams = { ...DEFAULT_HANABI_PARAMS, ...params };
  const resolvedSeed = String(seed ?? "hanabi");
  const instrumental = lines.length === 0;
  const lyric = instrumental ? null : planLyricParagraphs2(lines, resolvedParams, options.duration);
  const instrumentalDuration = Math.max(1, options.duration && options.duration > 0 ? options.duration : INSTRUMENTAL_DURATION2);
  const plans = lyric ? lyric.plans : planInstrumentalParagraphs2(instrumentalDuration);
  const chain = { recent: [], family: null };
  let previousTransition = null;
  const paragraphs = plans.map((plan, index) => {
    const planned = splitLongBridges2(closeTail(
      planShots2(plan.lines, plan.startTime, plan.endTime, resolvedParams),
      plan.endTime,
      resolvedParams
    ));
    const shots = planned.map((shot, shotIndex) => {
      const kind = castShot2({
        seed: resolvedSeed,
        paragraphIndex: index,
        shotIndex,
        kind: plan.kind,
        isBridge: shot.isBridge,
        chain
      });
      advanceChain2(chain, kind);
      return {
        id: `p${index}-hb${shotIndex}`,
        kind,
        slices: shot.slices,
        startTime: shot.startTime,
        endTime: shot.endTime,
        lyricEndTime: shot.lyricEndTime,
        isBridge: shot.isBridge
      };
    });
    const next = plans[index + 1];
    let transitionOut = null;
    if (next) {
      const kind = chooseHanabiTransition(resolvedSeed, index, previousTransition);
      previousTransition = kind;
      const gap = next.startTime - plan.lyricEndTime;
      transitionOut = {
        kind,
        startTime: Math.max(plan.startTime, plan.endTime - HANABI_TRANSITIONS[kind].duration(gap)),
        endTime: plan.endTime
      };
    }
    const lineIndices = [...new Set(shots.flatMap((shot) => shot.slices.map((slice) => slice.lineIndex)))].sort((a, b) => a - b);
    return {
      id: `hanabi-p${index}`,
      index,
      kind: plan.kind,
      startTime: plan.startTime,
      endTime: plan.endTime,
      lyricEndTime: plan.lyricEndTime,
      lineIndices,
      lines: lineIndices.map((lineIndex) => lines[lineIndex]),
      shots,
      transitionOut
    };
  });
  return {
    version: 1,
    seed: resolvedSeed,
    instrumental,
    duration: lyric ? lyric.programEnd : instrumentalDuration,
    lyricEndTime: lyric ? lyric.lyricEndTime : null,
    paragraphs,
    chorus: resolveHanabiChorusSpans(lines)
  };
};
var findHanabiParagraphIndexAtTime = (program, time) => {
  for (let index = program.paragraphs.length - 1; index >= 0; index -= 1) {
    if (time >= program.paragraphs[index].startTime) return index;
  }
  return 0;
};

// folia:src/services/beatFx/clock.ts
var BEAT_FX_WEAK_BEAT_FLOOR = 0.35;
var resolveBeatFxAccentGain = (event, trackScale) => {
  if (event?.rhythmic === false) return 0;
  if (!event || event.impact === void 0) return trackScale;
  return (BEAT_FX_WEAK_BEAT_FLOOR + (1 - BEAT_FX_WEAK_BEAT_FLOOR) * event.impact) * trackScale;
};

// folia:src/components/visualizer/hanabi/hanabiBeatFx.ts
var HANABI_BEAT_SHELL_LIFE = 1.8;
var BEAT_KINDS = ["botan", "senrin", "strobe", "star", "heart", "ring"];
var DOWNBEAT_KINDS = ["kiku", "ring", "willow-ring", "crossette", "palm"];
var resolveHanabiBeatShell = (event, seed, strength, trackScale) => {
  const gain = resolveBeatFxAccentGain(event, trackScale);
  if (gain <= 0 || strength <= 0) return null;
  const key = `${seed}:beat:${Math.round(event.t * 1e3)}`;
  const random = createRng2(key);
  const downbeat = event.kind === "downbeat";
  const kinds = downbeat ? DOWNBEAT_KINDS : BEAT_KINDS;
  const kind = kinds[Math.floor(random() * kinds.length)];
  const colors = [0, 1, 2].map((k) => (k + Math.floor(random() * 5)) % 5);
  const size = (0.55 + 0.45 * gain) * (0.7 + 0.3 * strength);
  const spec = downbeat ? { ...burstPreset(kind, colors), count: Math.round(80 * (0.5 + 0.5 * strength)), radius: 0.2 * size, duration: 1.7 } : { ...burstPreset(kind, colors), count: Math.round(28 * (0.5 + 0.5 * strength)), radius: 0.09 * size, duration: 1.1, trail: 0.25 };
  return {
    t: event.t,
    downbeat,
    // 小烟花散在夜空上半部与两侧，大的开在上方中间一带；都在字底色块后面。
    sx: downbeat ? 0.2 + random() * 0.6 : 0.06 + random() * 0.88,
    sy: downbeat ? 0.12 + random() * 0.2 : 0.07 + random() * 0.36,
    spec,
    launch: downbeat,
    seed: key
  };
};
var firstBeatAtOrAfter = (events, time) => {
  let low = 0;
  let high = events.length;
  while (low < high) {
    const middle = low + high >> 1;
    if (events[middle].t < time) low = middle + 1;
    else high = middle;
  }
  return low;
};
var HANABI_BEAT_PULSE = {
  /** 每拍推近的比例与重拍额外推近的比例（强度 1 时）。 */
  zoom: 0.035,
  downbeatZoom: 0.045,
  /** 每拍左右交替摆的角度（度，跟 beatFxLive 的 getBeatFxRotationSign 换边）。 */
  kickDeg: 1.6
};
var resolveHanabiBeatPulse = (k, d, rotationSign) => ({
  scale: 1 + HANABI_BEAT_PULSE.zoom * Math.max(0, k) + HANABI_BEAT_PULSE.downbeatZoom * Math.max(0, d),
  rotation: HANABI_BEAT_PULSE.kickDeg * Math.PI / 180 * Math.max(0, k) * rotationSign
});
var rescaleBeatEnvelope = (envelope, clockStrength, ownStrength) => clockStrength > 1e-3 ? envelope / clockStrength * ownStrength : 0;

// folia:src/components/visualizer/hanabi/collage/unitCollage.ts
var paintDotTile = (scale) => {
  const tile = 26;
  const canvas = document.createElement("canvas");
  canvas.width = Math.ceil(tile * scale);
  canvas.height = Math.ceil(tile * scale);
  const context = canvas.getContext("2d");
  context.setTransform(scale, 0, 0, scale, 0, 0);
  context.fillStyle = "#ffffff";
  context.beginPath();
  context.arc(tile / 4, tile / 4, 1.6, 0, Math.PI * 2);
  context.arc(tile * 3 / 4, tile * 3 / 4, 1.6, 0, Math.PI * 2);
  context.fill();
  return canvas;
};
var createUnitCollage = (pixi, options) => {
  const { width, height, amount } = options;
  const unit = Math.min(width, height);
  const random = createRng2(`${options.seed}:unit-collage`);
  const back = new pixi.Container();
  const front = new pixi.Container();
  const scale = Math.max(1, Math.min(2, options.resolution || 1));
  const dotTexture = new pixi.Texture({ source: new pixi.CanvasSource({ resource: paintDotTile(scale), resolution: scale }) });
  const dots = new pixi.TilingSprite({ texture: dotTexture, width: width * 1.2, height: height * 1.2 });
  dots.position.set(-width * 0.1, -height * 0.1);
  dots.tint = options.paper;
  dots.alpha = 0.05 + 0.03 * Math.min(1, amount);
  back.addChild(dots);
  const thickness = Math.max(20, unit * 0.055);
  const rail = new pixi.TilingSprite({
    texture: options.cache.strip("film", CANDY[Math.floor(random() * CANDY.length)], thickness),
    width: height * 1.3,
    height: thickness
  });
  rail.anchor.set(0.5);
  rail.rotation = -Math.PI / 2;
  rail.position.set(Math.max(thickness * 0.9, width * 0.022), height / 2);
  rail.alpha = 0.92;
  front.addChild(rail);
  const tile = rail.texture.width || 1;
  const drift = unit * 0.03;
  return {
    back,
    front,
    update: (time, rise) => {
      dots.tilePosition.y = rise * 0.35;
      rail.tilePosition.x = (-(rise + drift * (time - options.startTime)) % tile + tile) % tile;
    },
    destroy: () => {
      back.destroy({ children: true });
      front.destroy({ children: true });
      dotTexture.destroy(true);
    }
  };
};

// folia:src/components/visualizer/hanabi/mg/ambient.ts
var AMBIENT_PARALLAX = {
  starsNear: 0.42,
  starsFar: 0.2,
  smoke: 0.3,
  distant: 0.55,
  embers: 1.25,
  bokeh: 1.45
};
var parallaxY = (y0, rise, parallax, drift, height, margin) => wrap2(y0 + rise * parallax + drift + margin, height + margin * 2) - margin;
var DISTANT_KINDS = ["kiku", "botan", "ring", "yanagi", "senrin", "kamuro", "strobe", "kiku", "botan"];
var DISTANT_DURATION = 2.6;
var distantBurstAt = (seed, k, rate, startTime, width, span) => {
  const salt = hashString(seed) % 9973;
  const h = (i) => hash01(k * 17 + i, salt + 0.37);
  const at = startTime + (k + 0.1 + h(1) * 0.8) / rate;
  const kind = DISTANT_KINDS[Math.floor(h(2) * DISTANT_KINDS.length) % DISTANT_KINDS.length];
  const x = width * (0.06 + h(3) * 0.88);
  const y0 = span * h(4);
  return {
    at,
    x,
    y0,
    event: {
      x,
      y: 0,
      at,
      seed: `${seed}:distant:${k}`,
      scale: 1,
      squash: 0.35 + h(6) * 0.65,
      rotation: (h(7) - 0.5) * 0.8,
      spec: {
        kind,
        count: 26 + Math.floor(h(5) * 20),
        radius: 0.045 + h(8) * 0.045,
        duration: DISTANT_DURATION * (0.75 + h(9) * 0.25),
        colors: [Math.floor(h(10) * 5), Math.floor(h(11) * 5), Math.floor(h(12) * 5)],
        trail: 0.3 + h(13) * 0.4,
        twinkle: h(14) * 0.6
      }
    }
  };
};
var distantRange = (time, rate, startTime, endTime) => {
  if (rate <= 0) return [0, -1];
  const count = Math.max(0, Math.floor((endTime - startTime) * rate));
  const first = Math.max(0, Math.floor((time - DISTANT_DURATION - startTime) * rate) - 1);
  const last = Math.min(count - 1, Math.floor((time - startTime) * rate));
  return [first, last];
};
var tintedSpark = (palette, i) => palette.sparks[i % Math.max(1, palette.sparks.length)] ?? WHITE2;
var SMOKE_CROP = 0.8;
var createAmbient = (options) => {
  const { pixi, textures, width, height, palette } = options;
  const unit = Math.min(width, height);
  const density = Math.max(0, Math.min(2, options.density));
  const rng = createRng2(`${options.seed}:ambient`);
  const back = new pixi.Container({ isRenderGroup: true });
  const front = new pixi.Container({ isRenderGroup: true });
  const smokeLayer = new pixi.Container();
  const starLayer = new pixi.Container();
  const distantLayer = new pixi.Container();
  const distantFlashLayer = new pixi.Container();
  distantFlashLayer.blendMode = "add";
  back.addChild(smokeLayer, starLayer, distantLayer, distantFlashLayer);
  const emberLayer = new pixi.Container();
  const bokehLayer = new pixi.Container();
  front.addChild(bokehLayer, emberLayer);
  const margin = unit * 0.36;
  const span = height + margin * 2;
  const sprite = (texture, parent) => {
    const s = new pixi.Sprite(texture);
    s.anchor.set(0.5);
    parent.addChild(s);
    return s;
  };
  const dots = (count, parent, make) => Array.from({ length: count }, (_, i) => {
    const spec = make(i);
    const s = sprite(spec.texture, parent);
    s.tint = spec.tint;
    return { ...spec, sprite: s };
  });
  const starTint = mixColor(WHITE2, palette.glow, 0.25);
  const stars = dots(Math.round(110 * density), starLayer, () => {
    const bright = rng() < 0.08;
    const depth = rng();
    return {
      texture: bright ? textures.star4 : textures.dot,
      tint: bright ? mixColor(WHITE2, palette.glow, 0.4) : starTint,
      x: rng() * width,
      y0: rng() * span,
      size: unit * (bright ? 0.012 + rng() * 0.01 : 2e-3 + rng() * 4e-3),
      alpha: bright ? 0.7 : 0.2 + rng() * 0.55,
      parallax: AMBIENT_PARALLAX.starsFar + depth * (AMBIENT_PARALLAX.starsNear - AMBIENT_PARALLAX.starsFar),
      speed: 0,
      freq: 0.15 + rng() * 0.7,
      phase: rng() * TAU2,
      sway: 0
    };
  });
  const glowFrame = textures.glow.frame;
  const smokeTexture = new pixi.Texture({
    source: textures.glow.source,
    frame: new pixi.Rectangle(
      glowFrame.x + glowFrame.width * (1 - SMOKE_CROP) / 2,
      glowFrame.y + glowFrame.height * (1 - SMOKE_CROP) / 2,
      glowFrame.width * SMOKE_CROP,
      glowFrame.height * SMOKE_CROP
    )
  });
  const smoke = dots(Math.round(5 * Math.min(1.5, density)), smokeLayer, (i) => ({
    texture: smokeTexture,
    tint: mixColor(tintedSpark(palette, i), 10133684, 0.6),
    x: width * (0.1 + rng() * 0.8),
    y0: rng() * span,
    size: unit * (0.6 + rng() * 0.5) * SMOKE_CROP,
    alpha: 0.035 + rng() * 0.035,
    parallax: AMBIENT_PARALLAX.smoke,
    speed: 0,
    freq: 0.03 + rng() * 0.04,
    phase: rng() * TAU2,
    sway: unit * (0.05 + rng() * 0.08)
  }));
  const embers = dots(Math.round(40 * density), emberLayer, (i) => ({
    texture: textures.glow,
    tint: mixColor(GOLD, tintedSpark(palette, i), 0.3),
    x: rng() * width,
    y0: rng() * span,
    // glow 纹理的亮芯只占三成：画面上约 3–7 px 的火星。
    size: unit * (0.012 + rng() * 0.016),
    alpha: 0.55 + rng() * 0.45,
    parallax: AMBIENT_PARALLAX.embers + rng() * 0.1,
    speed: unit * (0.05 + rng() * 0.12),
    freq: 0.4 + rng() * 0.9,
    phase: rng() * TAU2,
    sway: unit * (8e-3 + rng() * 0.02)
  }));
  const bokeh = dots(Math.round(6 * density), bokehLayer, (i) => ({
    texture: textures.glow,
    tint: tintedSpark(palette, i + 2),
    x: rng() * width,
    y0: rng() * span,
    size: unit * (0.08 + rng() * 0.1),
    alpha: 0.06 + rng() * 0.08,
    parallax: AMBIENT_PARALLAX.bokeh,
    speed: unit * (0.01 + rng() * 0.02),
    freq: 0.1 + rng() * 0.2,
    phase: rng() * TAU2,
    sway: unit * 0.02
  }));
  const distantPools = [distantLayer, distantFlashLayer].map((layer) => ({ layer, sprites: [], used: 0, shown: 0 }));
  const distantMax = Math.round(240 * Math.min(1.5, density));
  const distantPlans = /* @__PURE__ */ new Map();
  let distantUsed = 0;
  let offsetY = 0;
  const distantTexture = {
    glow: textures.glow,
    dot: textures.dot,
    star4: textures.star4,
    streak: textures.streak,
    flash: textures.glow
  };
  const emitDistant = (texture, x, y, w, h, rotation, alpha, tint) => {
    if (distantUsed >= distantMax) return false;
    const pool = distantPools[texture === "flash" ? 1 : 0];
    let s = pool.sprites[pool.used];
    if (!s) {
      s = sprite(textures.glow, pool.layer);
      pool.sprites.push(s);
    }
    pool.used += 1;
    s.texture = distantTexture[texture];
    s.visible = true;
    s.position.set(x, y + offsetY);
    s.rotation = rotation;
    s.width = w;
    s.height = h;
    s.alpha = Math.min(1, alpha) * 0.6;
    s.tint = tint;
    distantUsed += 1;
    return true;
  };
  const activeDistant = [];
  const place = (dot, x, y, size, alpha) => {
    const visible = alpha > 4e-3 && y > -size && y < height + size;
    dot.sprite.visible = visible;
    if (!visible) return;
    dot.sprite.position.set(x, y);
    dot.sprite.width = size;
    dot.sprite.height = size;
    dot.sprite.alpha = alpha;
  };
  const update = (time, rise) => {
    for (const dot of stars) {
      const y = parallaxY(dot.y0, rise, dot.parallax, 0, height, margin);
      const twinkle = 0.55 + 0.45 * Math.sin(time * dot.freq * TAU2 + dot.phase);
      place(dot, dot.x, y, dot.size * (0.85 + 0.3 * twinkle), dot.alpha * twinkle);
    }
    for (const dot of smoke) {
      const y = parallaxY(dot.y0, rise, dot.parallax, -time * unit * 0.01, height, margin);
      const x = dot.x + Math.sin(time * dot.freq * TAU2 + dot.phase) * dot.sway;
      place(dot, x, y, dot.size * (1 + 0.1 * Math.sin(time * 0.2 + dot.phase)), dot.alpha);
    }
    for (const dot of embers) {
      const y = parallaxY(dot.y0, rise, dot.parallax, -time * dot.speed, height, margin);
      const x = dot.x + Math.sin(time * dot.freq * TAU2 + dot.phase) * dot.sway;
      const flicker = hash01(Math.floor(time * 14 + dot.phase * 10), dot.phase) < 0.25 ? 0.35 : 1;
      const fade = 0.35 + 0.65 * clamp017(y / height);
      place(dot, x, y, dot.size * (0.8 + 0.4 * flicker), dot.alpha * flicker * fade);
    }
    for (const dot of bokeh) {
      const y = parallaxY(dot.y0, rise, dot.parallax, -time * dot.speed, height, margin);
      const x = dot.x + Math.sin(time * dot.freq * TAU2 + dot.phase) * dot.sway;
      place(dot, x, y, dot.size, dot.alpha * (0.8 + 0.2 * Math.sin(time * 0.5 + dot.phase)));
    }
    distantUsed = 0;
    if (options.distantBursts > 0 && distantMax > 0) {
      const [first, last] = distantRange(time, options.distantBursts, options.startTime, options.endTime);
      for (const key of distantPlans.keys()) if (key < first || key > last) distantPlans.delete(key);
      for (let k = first; k <= last; k += 1) {
        let entry = distantPlans.get(k);
        if (!entry) {
          const burst2 = distantBurstAt(options.seed, k, options.distantBursts, options.startTime, width, span);
          entry = { burst: burst2, plan: planBurst(burst2.event, palette, { unit, amount: Math.min(1.5, density) }) };
          distantPlans.set(k, entry);
        }
        if (time < entry.plan.at || time > entry.plan.end) continue;
        offsetY = parallaxY(entry.burst.y0, rise, AMBIENT_PARALLAX.distant, 0, height, margin);
        activeDistant.length = 0;
        activeDistant.push(entry.plan);
        drawBursts(activeDistant, time, distantMax - distantUsed, emitDistant);
      }
    }
    for (const pool of distantPools) {
      for (let i = pool.used; i < pool.shown; i += 1) pool.sprites[i].visible = false;
      pool.shown = pool.used;
      pool.used = 0;
    }
  };
  return {
    back,
    front,
    update,
    destroy: () => {
      distantPlans.clear();
      back.destroy({ children: true });
      front.destroy({ children: true });
      smokeTexture.destroy(false);
    }
  };
};

// folia:src/components/visualizer/hanabi/mg/ornamentKit.ts
var createKit = (spec, ctx) => {
  const { pixi } = ctx;
  const view = new pixi.Container({ isRenderGroup: true });
  const rng = createRng2(`${ctx.seed}:ornament:${spec.kind}:${spec.placement}`);
  const start = ctx.enterAt + spec.delay;
  const end = ctx.exitAt + Math.max(0, ctx.exitDuration);
  const b = ctx.bounds;
  const cx = b.x + b.width / 2;
  const cy = b.y + b.height / 2;
  const hw = Math.max(1, b.width / 2);
  const hh = Math.max(1, b.height / 2);
  const initial = ctx.anchorsAt(ctx.enterAt);
  const landed = initial.reduce((max, anchor) => Math.max(max, anchor.landedAt), ctx.enterAt);
  const settle = Math.min(ctx.exitAt - 1e-3, landed + 0.05);
  const settled = settle > ctx.enterAt ? ctx.anchorsAt(settle) : initial;
  const glyphs = [];
  settled.forEach((anchor, index) => {
    if (anchor.blank) return;
    glyphs.push({
      index,
      char: anchor.char,
      x: anchor.x,
      y: anchor.y,
      size: anchor.size,
      sungAt: anchor.sungAt,
      sungEnd: anchor.sungEnd,
      landedAt: anchor.landedAt
    });
  });
  const sizes = glyphs.map((g) => g.size).sort((p, q) => p - q);
  const base = sizes.length > 0 ? sizes[Math.floor(sizes.length / 2)] : Math.max(12, Math.min(hw, hh) * 0.8, Math.min(ctx.width, ctx.height) * 0.06);
  const size = base * Math.max(0.1, spec.scale);
  let vertical = false;
  if (glyphs.length > 1) {
    const xs = glyphs.map((g) => g.x);
    const ys = glyphs.map((g) => g.y);
    vertical = Math.max(...ys) - Math.min(...ys) > (Math.max(...xs) - Math.min(...xs)) * 1.3;
  }
  const sung = glyphs.map((g) => g.sungAt).sort((p, q) => p - q);
  const factor = Math.max(0, ctx.amount) * (0.35 + 0.9 * clamp017(spec.density));
  const count = (baseCount, min = 1) => factor <= 0 ? 0 : Math.max(min, Math.round(baseCount * factor));
  const pick2 = (list, i, fallback) => list.length > 0 ? list[(i % list.length + list.length) % list.length] : fallback;
  const color = (i) => {
    const p = ctx.palette;
    switch (spec.color) {
      case "spark":
        return pick2(p.sparks, i, p.accent);
      case "block":
        return pick2(p.blocks, i, p.accent);
      case "paper":
        return p.paper;
      case "glow":
        return p.glow;
      default:
        return p.accent;
    }
  };
  const pad = base * 0.35;
  const sites = (mode, maxGlyphSites) => {
    const make = (x, y, w, h, angle, extra = {}) => ({
      x,
      y,
      w,
      h,
      angle,
      glyph: -1,
      start,
      hollow: false,
      ...extra
    });
    switch (spec.placement) {
      case "behind":
        return [make(cx, cy, hw, hh, -Math.PI / 2)];
      case "around":
        return [make(cx, cy, hw + pad, hh + pad, -Math.PI / 2, { hollow: mode === "scatter" })];
      case "corners":
        return [[-1, -1], [1, -1], [1, 1], [-1, 1]].map(([sx, sy], k) => make(
          cx + sx * (hw + pad * 0.6),
          cy + sy * (hh + pad * 0.6),
          base * 0.6,
          base * 0.6,
          Math.atan2(sy, sx),
          { start: start + k * 0.07 }
        ));
      case "line-start":
        return [vertical ? make(cx, cy - hh - pad, base * 0.7, base * 0.7, -Math.PI / 2) : make(cx - hw - pad, cy, base * 0.7, base * 0.7, Math.PI)];
      case "line-end":
        return [vertical ? make(cx, cy + hh + pad, base * 0.7, base * 0.7, Math.PI / 2) : make(cx + hw + pad, cy, base * 0.7, base * 0.7, 0)];
      case "screen":
        return [make(0, 0, ctx.width * 0.55, ctx.height * 0.55, -Math.PI / 2)];
      case "glyphs":
      default: {
        if (glyphs.length === 0) return [make(cx, cy, hw, hh, -Math.PI / 2)];
        const limit = Math.max(1, Math.min(glyphs.length, maxGlyphSites));
        const chosen = [];
        for (let i = 0; i < limit; i += 1) chosen.push(glyphs[Math.floor((i + 0.5) * glyphs.length / limit)]);
        return chosen.map((g) => make(g.x, g.y, g.size * 0.55, g.size * 0.55, -Math.PI / 2, {
          glyph: g.index,
          start: Math.max(start, g.sungAt)
        }));
      }
    }
  };
  let cachedTime = Number.NaN;
  let cached = settled;
  const anchors = (time) => {
    if (time !== cachedTime) {
      cachedTime = time;
      cached = ctx.anchorsAt(time);
    }
    return cached;
  };
  const pos = (site, list, out) => {
    const anchor = site.glyph >= 0 ? list[site.glyph] : void 0;
    if (anchor) {
      out.x = anchor.x;
      out.y = anchor.y;
      out.alpha = anchor.alpha;
      out.size = anchor.size;
    } else {
      out.x = site.x;
      out.y = site.y;
      out.alpha = 1;
      out.size = Math.max(site.w, site.h);
    }
    return out;
  };
  const exitSpan = Math.max(0.05, ctx.exitDuration);
  const exit = (time, stagger = 0) => clamp017((time - ctx.exitAt - stagger) / Math.max(0.05, exitSpan - stagger));
  const scatter = (site) => {
    if (!site.hollow) return [(rng() * 2 - 1) * site.w, (rng() * 2 - 1) * site.h];
    const ow = site.w + base * 1.3;
    const oh = site.h + base * 1;
    for (let tries = 0; tries < 12; tries += 1) {
      const x = (rng() * 2 - 1) * ow;
      const y = (rng() * 2 - 1) * oh;
      if (Math.abs(x) > site.w || Math.abs(y) > site.h) return [x, y];
    }
    const a = rng() * Math.PI * 2;
    return [Math.cos(a) * ow, Math.sin(a) * oh];
  };
  const lastSung = (time) => {
    let result = Number.NEGATIVE_INFINITY;
    for (const at of sung) {
      if (at > time) break;
      result = at;
    }
    return result;
  };
  const sprite = (texture, parent = view) => {
    const s = new pixi.Sprite(ctx.textures[texture]);
    s.anchor.set(0.5);
    parent.addChild(s);
    return s;
  };
  const graphics = (parent = view, context2) => {
    const g = context2 ? new pixi.Graphics(context2) : new pixi.Graphics();
    parent.addChild(g);
    return g;
  };
  const contexts = [];
  const context = () => {
    const c = new pixi.GraphicsContext();
    contexts.push(c);
    return c;
  };
  view.on("destroyed", () => contexts.forEach((c) => c.destroy()));
  return {
    spec,
    ctx,
    pixi,
    view,
    rng,
    start,
    end,
    size,
    glyphs,
    vertical,
    cx,
    cy,
    hw,
    hh,
    count,
    color,
    sites,
    anchors,
    pos,
    exit,
    scatter,
    lastSung,
    sprite,
    graphics,
    context
  };
};

// folia:src/components/visualizer/hanabi/mg/ornamentLines.ts
var newPos = () => ({ x: 0, y: 0, alpha: 1, size: 0 });
var tracksFor = (kit, reach, across) => {
  const pad = kit.size * 0.35;
  const { cx, cy, hw, hh, vertical, start } = kit;
  const along = (sign) => vertical ? { x: cx, y: cy + sign * (hh + pad), dx: 0, dy: sign, length: reach, glyph: -1, start } : { x: cx + sign * (hw + pad), y: cy, dx: sign, dy: 0, length: reach, glyph: -1, start };
  switch (kit.spec.placement) {
    case "line-start":
      return [along(-1)];
    case "line-end":
      return [along(1)];
    case "corners":
      return [[-1, -1], [1, -1], [1, 1], [-1, 1]].map(([sx, sy], k) => ({
        x: cx + sx * (hw + pad * 0.5),
        y: cy + sy * (hh + pad * 0.5),
        dx: sx * Math.SQRT1_2,
        dy: sy * Math.SQRT1_2,
        length: reach * 0.6,
        glyph: -1,
        start: start + k * 0.06
      }));
    case "screen": {
      const w = kit.ctx.width * 0.55;
      const h = kit.ctx.height * 0.55;
      return vertical ? [
        { x: cx - hw - pad * 2, y: -h, dx: 0, dy: 1, length: h * 2, glyph: -1, start },
        { x: cx + hw + pad * 2, y: h, dx: 0, dy: -1, length: h * 2, glyph: -1, start: start + 0.1 }
      ] : [
        { x: -w, y: cy - hh - pad * 2, dx: 1, dy: 0, length: w * 2, glyph: -1, start },
        { x: w, y: cy + hh + pad * 2, dx: -1, dy: 0, length: w * 2, glyph: -1, start: start + 0.1 }
      ];
    }
    default:
      if (across) {
        return vertical ? [{ x: cx + hw + pad, y: cy - hh - reach * 0.5, dx: 0, dy: 1, length: hh * 2 + reach, glyph: -1, start }] : [{ x: cx - hw - reach * 0.5, y: cy + hh + pad, dx: 1, dy: 0, length: hw * 2 + reach, glyph: -1, start }];
      }
      return [along(-1), along(1)];
  }
};
var strokeTrack = (g, track, from, to, steps, offset, ox = 0, oy = 0) => {
  if (to - from <= 1e-4) return false;
  const nx = -track.dy;
  const ny = track.dx;
  for (let i = 0; i <= steps; i += 1) {
    const s = lerp3(from, to, i / steps);
    const d = s * track.length;
    const o = offset(s);
    const x = track.x + ox + track.dx * d + nx * o;
    const y = track.y + oy + track.dy * d + ny * o;
    if (i === 0) g.moveTo(x, y);
    else g.lineTo(x, y);
  }
  return true;
};
var zigzagOrnament = (kit) => {
  const reach = kit.size * (2.6 + kit.rng() * 1.4);
  const tracks = tracksFor(kit, reach, false);
  const g = kit.graphics();
  g.tint = kit.color(0);
  const echo = kit.graphics();
  echo.tint = kit.color(1);
  const amp = kit.size * 0.18;
  const width = Math.max(1.5, kit.size * 0.06);
  return (time) => {
    g.clear();
    echo.clear();
    const x = kit.exit(time);
    let any = false;
    const flip = Math.floor(time * 6) % 2 === 0 ? 0 : 0.5;
    const pump = 1 + 0.3 * (Math.floor(time * 3) % 3 === 0 ? 1 : 0);
    for (const track of tracks) {
      const local = time - track.start;
      if (local < 0 || x >= 1) continue;
      const teeth = Math.max(3, Math.round(track.length / (kit.size * 0.34)));
      const to = easeOutCubic3(local / 0.5);
      const from = easeInCubic(x);
      const steps = teeth * 2;
      const zig = (s) => {
        const k = Math.round((s * teeth + flip) * 2);
        return (k % 2 === 0 ? 1 : -1) * amp * pump * Math.min(1, s * 6);
      };
      any = strokeTrack(g, track, from, to, steps, zig) || any;
      strokeTrack(echo, track, from, to * 0.8, steps, (s) => zig(s) * 0.6, -track.dy * amp * 1.8, track.dx * amp * 1.8);
    }
    if (any) {
      g.stroke({ width, color: 16777215, join: "miter", cap: "square" });
      echo.stroke({ width: width * 0.5, color: 16777215, join: "miter" });
    }
    g.visible = any;
    echo.visible = any;
    g.alpha = 1 - x;
    echo.alpha = 0.6 * (1 - x);
  };
};
var waveOrnament = (kit) => {
  const reach = kit.size * 4;
  const tracks = tracksFor(kit, reach, true);
  const layers = Math.min(3, Math.max(2, kit.count(2.4, 2)));
  const waves = Array.from({ length: layers }, (_, j) => {
    const g = kit.graphics();
    g.tint = kit.color(j);
    return { g, phase: j * 1.9, amp: kit.size * (0.22 - j * 0.05), speed: 0.6 + j * 0.25, width: Math.max(1.2, kit.size * (0.06 - j * 0.015)) };
  });
  const wavelength = kit.size * 1.6;
  return (time) => {
    const x = kit.exit(time);
    const bump = 1 + 0.6 * Math.exp(-(time - kit.lastSung(time)) / 0.25);
    waves.forEach((w, j) => {
      w.g.clear();
      let any = false;
      for (const track of tracks) {
        const local = time - track.start - j * 0.08;
        if (local < 0 || x >= 1) continue;
        const to = easeOutCubic3(local / 0.7);
        const from = easeInCubic(x);
        const steps = Math.min(140, Math.max(16, Math.round(track.length / (kit.size * 0.12))));
        const cycles = track.length / wavelength;
        any = strokeTrack(w.g, track, from, to, steps, (s) => Math.sin((s * cycles - time * w.speed) * TAU2 + w.phase) * w.amp * bump * Math.sin(Math.PI * s)) || any;
      }
      if (any) w.g.stroke({ width: w.width, color: 16777215, cap: "round", join: "round" });
      w.g.visible = any;
      w.g.alpha = (1 - x) * (j === 0 ? 1 : 0.65);
    });
  };
};
var underlineOrnament = (kit) => {
  const placement = kit.spec.placement;
  const thick = (size) => Math.max(2, size * 0.09 * kit.spec.scale);
  const vertical = kit.vertical;
  const bar = (sprite, x, y, length2, from, to, height, alpha) => {
    const visible = to - from > 2e-3 && alpha > 0.01;
    sprite.visible = visible;
    if (!visible) return;
    const mid = (from + to) / 2 * length2;
    const len = (to - from) * length2;
    if (vertical) {
      sprite.position.set(x, y + mid);
      sprite.width = height;
      sprite.height = len;
    } else {
      sprite.position.set(x + mid, y);
      sprite.width = len;
      sprite.height = height;
    }
    sprite.alpha = alpha;
  };
  if (placement === "glyphs" || placement === "corners" || kit.glyphs.length === 0) {
    const items = kit.glyphs.map((glyph, i) => {
      const main2 = kit.sprite("square");
      const echo2 = kit.sprite("square");
      main2.tint = kit.color(i);
      echo2.tint = kit.color(i + 1);
      return { glyph, main: main2, echo: echo2 };
    });
    return (time) => {
      const anchors = kit.anchors(time);
      const x = kit.exit(time);
      for (const it of items) {
        const anchor = anchors[it.glyph.index];
        const size = anchor?.size ?? it.glyph.size;
        const gx = anchor?.x ?? it.glyph.x;
        const gy = anchor?.y ?? it.glyph.y;
        const alpha = (anchor?.alpha ?? 1) * (1 - x);
        const local = time - it.glyph.sungAt;
        const retract = easeInCubic((time - it.glyph.sungEnd - 0.1) / 0.25);
        const grow = easeOutExpo2(local / 0.18);
        const length2 = size * 1.04;
        const ox = vertical ? gx + size * 0.6 : gx - length2 / 2;
        const oy = vertical ? gy - length2 / 2 : gy + size * 0.6;
        bar(it.main, ox, oy, length2, retract, local < 0 ? 0 : grow, thick(size), alpha);
        const growEcho = easeOutExpo2((local - 0.06) / 0.2);
        const retractEcho = easeInCubic((time - it.glyph.sungEnd - 0.16) / 0.25);
        bar(
          it.echo,
          ox + (vertical ? thick(size) * 1.6 : 0),
          oy + (vertical ? 0 : thick(size) * 1.6),
          length2,
          retractEcho,
          local < 0.06 ? 0 : growEcho,
          thick(size) * 0.35,
          alpha * 0.9
        );
      }
    };
  }
  const order = [...kit.glyphs].sort((a, b) => a.sungAt - b.sungAt);
  const first = order[0];
  const last = order[order.length - 1];
  const pad = kit.size * 0.3;
  const lineStart = placement === "line-start";
  const lineEnd = placement === "line-end";
  const main = kit.sprite("square");
  const echo = kit.sprite("square");
  main.tint = kit.color(0);
  echo.tint = kit.color(1);
  const length = vertical ? kit.hh * 2 : kit.hw * 2;
  const short = kit.size * 1.2;
  return (time) => {
    const x = kit.exit(time);
    let progress = 0;
    for (const glyph of order) {
      if (time >= glyph.sungAt) progress += clamp017((time - glyph.sungAt) / Math.max(0.08, glyph.sungEnd - glyph.sungAt));
    }
    const k = easeOutCubic3(progress / order.length);
    const retract = easeInCubic((time - last.sungEnd - 0.15) / 0.35);
    const pulse = 1 + 0.5 * Math.exp(-(time - kit.lastSung(time)) / 0.15);
    const height = thick(kit.size / kit.spec.scale) * (lineStart || lineEnd ? pulse : 1.2);
    const alpha = (1 - x) * (time >= first.sungAt ? 1 : 0);
    if (lineStart || lineEnd) {
      const bx2 = vertical ? kit.cx - short / 2 : lineStart ? kit.cx - kit.hw - pad - short : kit.cx + kit.hw + pad;
      const by2 = vertical ? lineStart ? kit.cy - kit.hh - pad - short : kit.cy + kit.hh + pad : kit.cy - short / 2;
      const grow = easeOutBack((time - first.sungAt) / 0.3, 2);
      bar(main, vertical ? kit.cx : bx2, vertical ? by2 : kit.cy, short, retract, grow, height, alpha);
      echo.visible = false;
      return;
    }
    const bx = vertical ? kit.cx + kit.hw + pad : kit.cx - kit.hw;
    const by = vertical ? kit.cy - kit.hh : kit.cy + kit.hh + pad;
    bar(main, bx, by, length, retract, k, height, alpha);
    bar(echo, bx + (vertical ? height * 1.6 : 0), by + (vertical ? 0 : height * 1.6), length, retract, Math.max(0, k - 0.04), height * 0.35, alpha * 0.9);
  };
};
var dotsLineOrnament = (kit) => {
  const placement = kit.spec.placement;
  const vertical = kit.vertical;
  const spacing = kit.size * 0.3;
  const dots = [];
  const litOf = (along) => {
    let best = Number.POSITIVE_INFINITY;
    let at = kit.start + 0.6;
    for (const glyph of kit.glyphs) {
      const d = Math.abs((vertical ? glyph.y : glyph.x) - along);
      if (d < best) {
        best = d;
        at = glyph.sungAt;
      }
    }
    return at;
  };
  const push = (x, y, order, litAt, size, glyph = null) => {
    const sprite = kit.sprite("dot");
    sprite.tint = kit.color(dots.length);
    dots.push({ sprite, x, y, glyph, order, litAt, size });
  };
  const pad = kit.size * 0.45;
  const lineAlong = (fromX, fromY, dx, dy, length, fade) => {
    const n = Math.max(3, Math.min(kit.count(48, 8), Math.round(length / spacing)));
    for (let i = 0; i < n; i += 1) {
      const s = n === 1 ? 0 : i / (n - 1);
      const x = fromX + dx * s * length;
      const y = fromY + dy * s * length;
      push(x, y, s, litOf(vertical ? y : x), kit.size * (fade ? 0.14 * (1 - s * 0.7) : 0.12));
    }
  };
  if (placement === "glyphs") {
    kit.glyphs.forEach((glyph, i) => push(
      vertical ? glyph.size * 0.62 : 0,
      vertical ? 0 : glyph.size * 0.62,
      i / Math.max(1, kit.glyphs.length - 1),
      glyph.sungAt,
      kit.size * 0.16,
      glyph
    ));
  } else if (placement === "line-start" || placement === "line-end") {
    const sign = placement === "line-start" ? -1 : 1;
    const length = kit.size * 3;
    if (vertical) lineAlong(kit.cx, kit.cy + sign * (kit.hh + pad), 0, sign, length, true);
    else lineAlong(kit.cx + sign * (kit.hw + pad), kit.cy, sign, 0, length, true);
  } else if (placement === "screen") {
    const w = kit.ctx.width * 0.5;
    if (vertical) lineAlong(kit.cx + kit.hw + pad * 2, -kit.ctx.height * 0.5, 0, 1, kit.ctx.height, false);
    else lineAlong(-w, kit.cy + kit.hh + pad * 1.8, 1, 0, w * 2, false);
  } else if (placement === "corners") {
    const arm = kit.size * 1.5;
    for (const [sx, sy] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
      const x0 = kit.cx + sx * (kit.hw + pad);
      const y0 = kit.cy + sy * (kit.hh + pad);
      lineAlong(x0, y0, -sx, 0, arm, true);
      lineAlong(x0, y0, 0, -sy, arm * 0.7, true);
    }
  } else {
    if (vertical) lineAlong(kit.cx + kit.hw + pad, kit.cy - kit.hh, 0, 1, kit.hh * 2, false);
    else lineAlong(kit.cx - kit.hw, kit.cy + kit.hh + pad, 1, 0, kit.hw * 2, false);
    if (placement === "around") {
      if (vertical) lineAlong(kit.cx - kit.hw - pad, kit.cy + kit.hh, 0, -1, kit.hh * 2, false);
      else lineAlong(kit.cx + kit.hw, kit.cy - kit.hh - pad, -1, 0, kit.hw * 2, false);
    }
  }
  const p = newPos();
  return (time) => {
    const anchors = kit.anchors(time);
    const x = kit.exit(time);
    const runner = fract2((time - kit.start) / 2.4);
    for (const d of dots) {
      const appear = time - kit.start - d.order * 0.5;
      const off = x * 1.4 - d.order * 0.4 >= 0.5;
      if (appear < 0 || off) {
        d.sprite.visible = false;
        continue;
      }
      let px = d.x;
      let py = d.y;
      let alpha = 1;
      if (d.glyph) {
        const anchor = anchors[d.glyph.index];
        px += anchor?.x ?? d.glyph.x;
        py += anchor?.y ?? d.glyph.y;
        alpha = anchor?.alpha ?? 1;
      }
      const lit = time >= d.litAt;
      const pop = lit ? 1 + 0.8 * Math.exp(-(time - d.litAt) / 0.12) : 1;
      const run = Math.max(0, 1 - Math.abs(runner - d.order) * 12);
      const size = d.size * (lit ? 1 : 0.6) * pop * easeOutBack(appear / 0.2, 2.5) * (1 + run * 0.6);
      d.sprite.visible = size > 0.3;
      d.sprite.position.set(px, py);
      d.sprite.width = size;
      d.sprite.height = size;
      d.sprite.alpha = alpha * (lit ? 1 : 0.35 + run * 0.5) * p.alpha;
    }
  };
};

// folia:src/components/visualizer/hanabi/mg/ornamentParticles.ts
var newPos2 = () => ({ x: 0, y: 0, alpha: 1, size: 0 });
var triggers = (kit, count) => {
  if (kit.glyphs.length > 0) {
    const limit = Math.max(1, Math.min(kit.glyphs.length, count));
    return Array.from({ length: limit }, (_, i) => {
      const g = kit.glyphs[Math.floor((i + 0.5) * kit.glyphs.length / limit)];
      return { at: Math.max(kit.start, g.sungAt), glyph: g };
    });
  }
  const span = Math.max(0.5, kit.ctx.exitAt - kit.start);
  return Array.from({ length: count }, (_, i) => ({ at: kit.start + span * i / count, glyph: null }));
};
var sparkleOrnament = (kit) => {
  const onGlyph = kit.spec.placement === "glyphs";
  const sites = kit.sites("scatter", 1);
  const items = triggers(kit, kit.count(14, 3)).map((trigger, i) => {
    const main = kit.sprite("star4");
    const satA = kit.sprite("star4");
    const satB = kit.sprite("dot");
    [main, satA, satB].forEach((s, k) => {
      s.tint = kit.color(i + k);
    });
    const side = kit.rng() < 0.5 ? -1 : 1;
    const site = sites[i % sites.length];
    const [sx, sy] = kit.scatter(site);
    return {
      main,
      satA,
      satB,
      trigger,
      site,
      side,
      ox: onGlyph ? side * 0.48 : sx,
      oy: onGlyph ? -0.45 - kit.rng() * 0.1 : sy,
      size: kit.size * (0.55 + kit.rng() * 0.35),
      spin: (kit.rng() - 0.5) * 1.2
    };
  });
  const p = newPos2();
  return (time) => {
    const anchors = kit.anchors(time);
    items.forEach((it, i) => {
      const local = time - it.trigger.at;
      const x = kit.exit(time, i % 6 * 0.03);
      if (local < 0 || x >= 1) {
        it.main.visible = false;
        it.satA.visible = false;
        it.satB.visible = false;
        return;
      }
      let cx;
      let cy;
      let alpha = 1;
      if (onGlyph && it.trigger.glyph) {
        const anchor = anchors[it.trigger.glyph.index];
        const size = anchor?.size ?? it.trigger.glyph.size;
        cx = (anchor?.x ?? it.trigger.glyph.x) + it.ox * size;
        cy = (anchor?.y ?? it.trigger.glyph.y) + it.oy * size;
        alpha = anchor?.alpha ?? 1;
      } else {
        kit.pos(it.site, anchors, p);
        cx = p.x + it.ox;
        cy = p.y + it.oy;
      }
      const pop = spring(local, 3.2, 8);
      const settle = clamp017((local - 0.45) / 0.35);
      const idle = 0.32 + 0.1 * Math.sin(time * 5 + i * 1.7);
      const scale = lerp3(1.25 * pop, idle, easeOutCubic3(settle)) * (1 - easeInCubic(x));
      const s = it.size * Math.max(0, scale);
      it.main.visible = s > 0.5;
      it.main.position.set(cx, cy);
      it.main.width = s;
      it.main.height = s;
      it.main.rotation = -Math.PI / 4 * (1 - easeOutCubic3(local / 0.3)) + it.spin * local + x * 3;
      it.main.alpha = alpha * (1 - x);
      const sat = (sprite, delay, dx, dy, sizeK) => {
        const l = local - delay;
        const k = clamp017(l / 0.5);
        sprite.visible = l >= 0 && k < 1;
        if (!sprite.visible) return;
        const ss = it.size * sizeK * Math.sin(Math.PI * k);
        sprite.position.set(cx + dx * it.size, cy + dy * it.size);
        sprite.width = ss;
        sprite.height = ss;
        sprite.alpha = alpha;
      };
      sat(it.satA, 0.08, it.side * 0.55, 0.35, 0.45);
      sat(it.satB, 0.15, -it.side * 0.4, -0.5, 0.16);
    });
  };
};
var crossOrnament = (kit) => {
  const shape = kit.context();
  shape.rect(-5, -1.4, 10, 2.8).rect(-1.4, -5, 2.8, 10).fill({ color: 16777215 });
  const oneShot = kit.spec.placement === "glyphs";
  const sites = kit.sites("scatter", 8);
  const n = oneShot ? sites.length * 2 : kit.count(12, 4);
  const items = Array.from({ length: n }, (_, i) => {
    const site = sites[i % sites.length];
    const [ox, oy] = oneShot ? [(kit.rng() - 0.5) * site.w * 3, -site.h * (0.9 + kit.rng() * 0.6)] : kit.scatter(site);
    const g = kit.graphics(kit.view, shape);
    g.tint = kit.color(i);
    return {
      g,
      site,
      ox,
      oy,
      size: kit.size * (0.18 + kit.rng() * 0.22) / 10,
      delay: oneShot ? i >= sites.length ? 0.08 : 0 : i * 0.06,
      offset: kit.rng(),
      rise: kit.size * (0.1 + kit.rng() * 0.2)
    };
  });
  const p = newPos2();
  return (time) => {
    const anchors = kit.anchors(time);
    items.forEach((it, i) => {
      const local = time - it.site.start - it.delay;
      const x = kit.exit(time, i % 8 * 0.03);
      if (local < 0 || x >= 1 || oneShot && local > 1.4) {
        it.g.visible = false;
        return;
      }
      kit.pos(it.site, anchors, p);
      let scale = easeOutBack(local / 0.3, 3) * (1 - easeInCubic(x));
      let alpha = p.alpha * (1 - x);
      if (oneShot) {
        const k = clamp017((local - 0.6) / 0.8);
        scale *= 1 - k;
        alpha *= 1 - k;
      }
      it.g.visible = scale > 0.01;
      it.g.position.set(p.x + it.ox, p.y + it.oy - it.rise * Math.sin(time * 0.8 + it.offset * TAU2));
      it.g.scale.set(Math.max(1e-3, it.size * scale));
      it.g.rotation = beatSteps(local / 1.2 + it.offset) * (Math.PI / 2) + x * 4;
      it.g.alpha = alpha;
    });
  };
};
var fallerLayout = (kit, site) => {
  const top = -site.h - kit.size * 2;
  const bottom = site.h + kit.size * 1.5;
  return { top, bottom };
};
var confettiOrnament = (kit) => {
  const sites = kit.sites("scatter", 6);
  const n = kit.count(26, 8);
  const pieces = Array.from({ length: n }, (_, i) => {
    const site = sites[i % sites.length];
    const sprite = kit.sprite(i % 3 === 2 ? "triangle" : "square");
    sprite.tint = kit.color(i);
    const angle = -Math.PI / 2 + (kit.rng() - 0.5) * 2.4;
    const speed = kit.size * (3 + kit.rng() * 4);
    return {
      sprite,
      site,
      x0: (kit.rng() * 2 - 1) * (site.w + kit.size),
      period: 3 + kit.rng() * 2.5,
      offset: kit.rng(),
      sway: kit.size * (0.2 + kit.rng() * 0.35),
      swayFreq: 0.4 + kit.rng() * 0.5,
      flip: 3 + kit.rng() * 6,
      spin: (kit.rng() - 0.5) * 6,
      size: kit.size * (0.2 + kit.rng() * 0.14),
      aspect: i % 3 === 2 ? 1 : 0.5 + kit.rng() * 0.3,
      delay: i % 5 * 0.02,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed
    };
  });
  const p = newPos2();
  const burstLife = 2.2;
  return (time) => {
    const anchors = kit.anchors(time);
    const x = kit.exit(time);
    for (const it of pieces) {
      const local = time - it.site.start - it.delay;
      if (local < 0 || x >= 1) {
        it.sprite.visible = false;
        continue;
      }
      kit.pos(it.site, anchors, p);
      const { top, bottom } = fallerLayout(kit, it.site);
      let ox;
      let oy;
      let alpha = 1;
      if (local < burstLife) {
        const drag = 2.6;
        const fall = kit.size * 1.6;
        const e = Math.exp(-drag * local);
        const f = (1 - e) / drag;
        ox = it.vx * f + Math.sin(local * it.swayFreq * TAU2) * it.sway * (1 - e);
        oy = it.vy * f + fall * (local - f);
        alpha = 1 - clamp017((local - burstLife + 0.4) / 0.4);
      } else {
        const cycle = fract2((local - burstLife) / it.period + it.offset);
        ox = it.x0 + Math.sin(local * it.swayFreq * TAU2) * it.sway;
        oy = lerp3(top, bottom, cycle);
        alpha = clamp017(cycle / 0.1) * clamp017((1 - cycle) / 0.15);
      }
      oy += kit.size * 3 * x * x;
      const flip = Math.cos(local * it.flip);
      it.sprite.visible = alpha > 0.01;
      it.sprite.position.set(p.x + ox, p.y + oy);
      it.sprite.width = it.size * Math.max(0.08, Math.abs(flip));
      it.sprite.height = it.size * it.aspect;
      it.sprite.rotation = local * it.spin;
      it.sprite.alpha = alpha * (1 - x) * p.alpha * (0.75 + 0.25 * Math.abs(flip));
    }
  };
};
var petalsOrnament = (kit) => {
  const sites = kit.sites("scatter", 4);
  const n = kit.count(16, 5);
  const petals = Array.from({ length: n }, (_, i) => {
    const site = sites[i % sites.length];
    const sprite = kit.sprite("petal");
    sprite.tint = kit.color(i);
    return {
      sprite,
      site,
      x0: (kit.rng() * 2 - 1) * (site.w + kit.size * 1.5),
      period: 4.5 + kit.rng() * 3,
      offset: kit.rng(),
      sway: kit.size * (0.3 + kit.rng() * 0.4),
      swayFreq: 0.25 + kit.rng() * 0.3,
      flip: 1.5 + kit.rng() * 2.5,
      spin: (kit.rng() - 0.5) * 2,
      size: kit.size * (0.22 + kit.rng() * 0.16),
      aspect: 1.35,
      delay: i * 0.05,
      vx: 0,
      vy: 0
    };
  });
  const p = newPos2();
  return (time) => {
    const anchors = kit.anchors(time);
    const x = kit.exit(time);
    for (const it of petals) {
      const local = time - it.site.start - it.delay;
      if (local < 0 || x >= 1) {
        it.sprite.visible = false;
        continue;
      }
      kit.pos(it.site, anchors, p);
      const { top, bottom } = fallerLayout(kit, it.site);
      const cycle = fract2(local / it.period + it.offset);
      const span = it.site.w + kit.size * 2;
      const drift = wrap2(it.x0 + span + cycle * kit.size * 2.5 + span, span * 2) - span;
      const ox = drift + Math.sin(local * it.swayFreq * TAU2) * it.sway + kit.size * 6 * x * x;
      const oy = lerp3(top, bottom, cycle);
      const flip = Math.cos(local * it.flip);
      const alpha = clamp017(cycle / 0.1) * clamp017((1 - cycle) / 0.15) * clamp017(local / 0.3);
      const pop = easeOutBack(local / 0.35, 2);
      it.sprite.visible = alpha > 0.01;
      it.sprite.position.set(p.x + ox, p.y + oy);
      it.sprite.width = it.size * Math.max(0.1, Math.abs(flip)) * pop;
      it.sprite.height = it.size * it.aspect * pop;
      it.sprite.rotation = 0.6 + Math.sin(local * 0.9 + it.offset * TAU2) * 0.7 + local * it.spin * 0.2;
      it.sprite.alpha = alpha * (1 - x) * p.alpha * 0.9;
    }
  };
};
var shardsOrnament = (kit) => {
  const oneShot = kit.spec.placement === "glyphs";
  const big = kit.spec.placement === "behind" || kit.spec.placement === "around" || kit.spec.placement === "screen";
  const sites = kit.sites("single", 8);
  const per = oneShot ? 4 : Math.max(3, Math.round(kit.count(18, 5) / sites.length));
  const shards2 = sites.flatMap((site, si) => Array.from({ length: per }, (_, i) => {
    const angle = TAU2 * (i + kit.rng() * 0.8) / per + si;
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);
    const edge = big ? 1 / Math.sqrt((cos / (site.w + kit.size * 0.2)) ** 2 + (sin / (site.h + kit.size * 0.2)) ** 2) : site.w * 0.8;
    const sprite = kit.sprite("triangle");
    sprite.tint = kit.color(si + i);
    return {
      sprite,
      site,
      cos,
      sin,
      edge,
      reach: kit.size * (oneShot ? 0.6 + kit.rng() * 0.6 : 0.8 + kit.rng() * 1.6),
      size: kit.size * (oneShot ? 0.14 + kit.rng() * 0.1 : 0.18 + kit.rng() * 0.22),
      rot: kit.rng() * TAU2,
      spin: (kit.rng() - 0.5) * 10,
      stretch: 1.3 + kit.rng() * 0.8
    };
  }));
  const p = newPos2();
  return (time) => {
    const anchors = kit.anchors(time);
    const x = kit.exit(time);
    for (const s of shards2) {
      const local = time - s.site.start;
      if (local < 0 || x >= 1 || oneShot && local > 1.1) {
        s.sprite.visible = false;
        continue;
      }
      kit.pos(s.site, anchors, p);
      const out = s.reach * (1 - Math.exp(-5 * local)) + kit.size * 0.08 * local + kit.size * 4 * easeInCubic(x);
      const r = s.edge + out;
      let scale = easeOutBack(local / 0.2, 2) * lerp3(1, 0.7, clamp017(local / 3)) * (1 - x);
      let alpha = p.alpha * (1 - x);
      if (oneShot) {
        const k = clamp017((local - 0.4) / 0.7);
        scale *= 1 - k;
        alpha *= 1 - k;
      }
      s.sprite.visible = scale > 0.01;
      s.sprite.position.set(p.x + s.cos * r, p.y + s.sin * r);
      s.sprite.width = s.size * scale;
      s.sprite.height = s.size * scale * s.stretch;
      s.sprite.rotation = s.rot + s.spin * (1 - Math.exp(-2 * local)) + 0.2 * local;
      s.sprite.alpha = alpha;
    }
  };
};
var streaksOrnament = (kit) => {
  const sites = kit.sites("scatter", 6);
  const n = kit.count(kit.spec.placement === "screen" ? 30 : 20, 6);
  const lines = Array.from({ length: n }, (_, i) => {
    const site = sites[i % sites.length];
    const [ox] = kit.scatter(site);
    const sprite = kit.sprite("streak");
    sprite.rotation = Math.PI;
    sprite.tint = kit.color(i);
    return {
      sprite,
      site,
      ox,
      y0: kit.rng(),
      length: kit.size * (1.4 + kit.rng() * 2.6),
      thick: Math.max(1, kit.size * (0.025 + kit.rng() * 0.05)),
      speed: kit.size * (5 + kit.rng() * 7),
      delay: kit.rng() * 0.3,
      salt: i * 13 + 1
    };
  });
  const p = newPos2();
  return (time) => {
    const anchors = kit.anchors(time);
    const x = kit.exit(time);
    for (const l of lines) {
      const local = time - l.site.start - l.delay;
      if (local < 0 || x >= 1) {
        l.sprite.visible = false;
        continue;
      }
      kit.pos(l.site, anchors, p);
      const top = -l.site.h - kit.size * 2 - l.length;
      const span = l.site.h * 2 + kit.size * 4 + l.length * 2;
      const travel = l.speed * (local + 2 * x * x);
      const y = top + wrap2(l.y0 * span + travel, span);
      const cycle = (y - top) / span;
      const window2 = clamp017(cycle / 0.15) * clamp017((1 - cycle) / 0.15);
      const flicker = hash01(Math.floor(time * 15), l.salt) < 0.2 ? 0.3 : 1;
      l.sprite.visible = window2 > 0.01;
      l.sprite.position.set(p.x + l.ox, p.y + y);
      l.sprite.width = l.thick;
      l.sprite.height = l.length * (1 + x);
      l.sprite.alpha = window2 * flicker * clamp017(local / 0.25) * (1 - x) * p.alpha * 0.85;
    }
  };
};
var chevronsOrnament = (kit) => {
  const shape = kit.context();
  shape.moveTo(-5, 3).lineTo(0, -2).lineTo(5, 3).stroke({ width: 2.4, color: 16777215, cap: "square", join: "miter" });
  const placement = kit.spec.placement;
  let columns;
  const sites = kit.sites("single", 6);
  if (placement === "around") {
    const site = sites[0];
    columns = [-1, 1].map((side) => ({ site, dx: side * (site.w + kit.size * 0.8), scale: 1, alpha: 1 }));
  } else if (placement === "screen") {
    const site = sites[0];
    columns = [-0.4, -0.2, 0.2, 0.4].map((k) => ({ site, dx: k * kit.ctx.width, scale: 1.2, alpha: 0.7 }));
  } else if (placement === "behind") {
    columns = [{ site: sites[0], dx: 0, scale: 2.2, alpha: 0.35 }];
  } else {
    columns = sites.map((site) => ({ site, dx: 0, scale: placement === "glyphs" ? 0.6 : 1, alpha: 1 }));
  }
  const perColumn = Math.max(2, Math.min(6, kit.count(4, 2)));
  const oneShot = placement === "glyphs";
  const spacing = kit.size * 0.42;
  const items = columns.flatMap((col, ci) => Array.from({ length: perColumn }, (_, j) => {
    const g = kit.graphics(kit.view, shape);
    g.tint = kit.color(ci + j);
    return { g, col, j };
  }));
  const p = newPos2();
  return (time) => {
    const anchors = kit.anchors(time);
    const x = kit.exit(time);
    for (const it of items) {
      const { col, j } = it;
      const local = time - col.site.start - j * 0.05;
      if (local < 0 || x >= 1 || oneShot && local > 1.6) {
        it.g.visible = false;
        continue;
      }
      kit.pos(col.site, anchors, p);
      const s = spacing * col.scale;
      const total = perColumn * s;
      const travel = beatSteps(local * 3.2, 0.4) * s * 0.5 + x * x * s * 6;
      const y = wrap2(j * s - travel, total);
      const k = y / total;
      const fade = Math.sin(Math.PI * clamp017(k));
      const pop = easeOutBack(local / 0.3, 2.4);
      const baseY = oneShot ? p.y - p.size * 0.8 - total * 0.5 : p.y - total / 2;
      it.g.visible = true;
      it.g.position.set(p.x + col.dx, baseY + y);
      it.g.scale.set(Math.max(1e-3, kit.size * 0.06 * col.scale * pop));
      let alpha = fade * col.alpha * (1 - x) * p.alpha;
      if (oneShot) alpha *= 1 - clamp017((local - 1) / 0.6);
      it.g.alpha = alpha;
    }
  };
};
var aroundBox = (u, halfW, halfH) => {
  const perimeter = 4 * (halfW + halfH);
  let d = fract2(u) * perimeter;
  if (d < 2 * halfW) return [-halfW + d, -halfH];
  d -= 2 * halfW;
  if (d < 2 * halfH) return [halfW, -halfH + d];
  d -= 2 * halfH;
  if (d < 2 * halfW) return [halfW - d, halfH];
  d -= 2 * halfW;
  return [-halfW, halfH - d];
};
var glintsOrnament = (kit) => {
  const onGlyph = kit.spec.placement === "glyphs" || kit.glyphs.length === 0;
  const run = 0.55;
  if (onGlyph) {
    const items = triggers(kit, kit.count(16, 4)).map((trigger, i) => {
      const head = kit.sprite("glow");
      const tail = kit.sprite("dot");
      const spark = kit.sprite("star4");
      [head, tail, spark].forEach((s) => {
        s.tint = kit.color(i);
      });
      return { head, tail, spark, trigger, corner: Math.floor(kit.rng() * 4) / 4 };
    });
    const site = kit.sites("single", 1)[0];
    const p2 = newPos2();
    return (time) => {
      const anchors = kit.anchors(time);
      const x = kit.exit(time);
      items.forEach((it) => {
        const local = time - it.trigger.at;
        const hide = local < 0 || x >= 1;
        it.head.visible = !hide;
        it.tail.visible = !hide;
        it.spark.visible = !hide;
        if (hide) return;
        let gx;
        let gy;
        let size;
        let alpha = 1;
        if (it.trigger.glyph) {
          const anchor = anchors[it.trigger.glyph.index];
          gx = anchor?.x ?? it.trigger.glyph.x;
          gy = anchor?.y ?? it.trigger.glyph.y;
          size = anchor?.size ?? it.trigger.glyph.size;
          alpha = anchor?.alpha ?? 1;
        } else {
          kit.pos(site, anchors, p2);
          gx = p2.x;
          gy = p2.y;
          size = kit.size;
        }
        const half = size * 0.56;
        const k = clamp017(local / run);
        const running = k < 1;
        const u = easeOutCubic3(k);
        const [hx, hy] = aroundBox(u, half, half);
        const [tx, ty] = aroundBox(Math.max(0, u - 0.08), half, half);
        const hs = kit.size * 0.35;
        it.head.visible = running;
        it.tail.visible = running;
        if (running) {
          it.head.position.set(gx + hx, gy + hy);
          it.head.width = hs;
          it.head.height = hs;
          it.head.alpha = alpha;
          it.tail.position.set(gx + tx, gy + ty);
          it.tail.width = hs * 0.25;
          it.tail.height = hs * 0.25;
          it.tail.alpha = alpha * 0.7;
        }
        const [cx, cy] = aroundBox(it.corner, half, half);
        const after = local - run;
        const twinkle = after < 0 ? 0 : spring(after, 2.5, 6) * (0.55 + 0.45 * Math.sin(time * 7 + it.corner * 20));
        const ss = kit.size * 0.4 * twinkle * (1 - easeInCubic(x));
        it.spark.visible = ss > 0.5;
        it.spark.position.set(gx + cx, gy + cy);
        it.spark.width = ss;
        it.spark.height = ss;
        it.spark.alpha = alpha * (1 - x);
      });
    };
  }
  const sites = kit.sites("single", 1);
  const runners = sites.flatMap((site, si) => [0, 0.5].map((phase, r) => {
    const head = kit.sprite("glow");
    const tails = [kit.sprite("dot"), kit.sprite("dot"), kit.sprite("dot")];
    [head, ...tails].forEach((s) => {
      s.tint = kit.color(si + r);
    });
    return { site, phase, head, tails };
  }));
  const p = newPos2();
  return (time) => {
    const anchors = kit.anchors(time);
    const x = kit.exit(time);
    const boost = Math.exp(-(time - kit.lastSung(time)) / 0.2);
    for (const r of runners) {
      const local = time - r.site.start;
      const hide = local < 0 || x >= 1;
      r.head.visible = !hide;
      r.tails.forEach((t) => {
        t.visible = !hide;
      });
      if (hide) continue;
      kit.pos(r.site, anchors, p);
      const halfW = r.site.w + kit.size * 0.15;
      const halfH = r.site.h + kit.size * 0.15;
      const u = r.phase + local / 2.8 + 0.1 * beatSteps(local * 1.2, 0.3) / 1.2;
      const alpha = clamp017(local / 0.2) * (1 - x) * p.alpha;
      const [hx, hy] = aroundBox(u, halfW, halfH);
      const hs = kit.size * (0.3 + 0.25 * boost);
      r.head.position.set(p.x + hx, p.y + hy);
      r.head.width = hs;
      r.head.height = hs;
      r.head.alpha = alpha;
      r.tails.forEach((t, k) => {
        const [tx, ty] = aroundBox(u - 0.012 * (k + 1), halfW, halfH);
        const ts = hs * 0.3 * (1 - k * 0.25);
        t.position.set(p.x + tx, p.y + ty);
        t.width = ts;
        t.height = ts;
        t.alpha = alpha * (0.7 - k * 0.2);
      });
    }
  };
};

// folia:src/components/visualizer/hanabi/mg/ornamentShapes.ts
var newPos3 = () => ({ x: 0, y: 0, alpha: 1, size: 0 });
var siteRadius = (placement, site, fallback) => {
  if (placement === "behind") return Math.hypot(site.w, site.h) * 0.8;
  if (placement === "around") return Math.hypot(site.w, site.h) * 0.95;
  if (placement === "screen") return Math.min(site.w, site.h) * 0.75;
  return Math.max(site.w, fallback) * 1.3;
};
var ringOrnament = (kit) => {
  const oneShot = kit.spec.placement === "glyphs";
  const layers = oneShot ? 1 : Math.min(3, kit.count(2.4, 1));
  const line2 = Math.max(1.5, kit.size * 0.055);
  const units = kit.sites("single", 8).map((site, si) => {
    const radius = siteRadius(kit.spec.placement, site, kit.size * 0.5) * (oneShot ? 1.3 : 1);
    const rings2 = Array.from({ length: layers }, (_, j) => {
      const g = kit.graphics();
      g.circle(0, 0, radius * (1 + 0.14 * j)).stroke({ width: line2 * (j === 0 ? 1.6 : 0.8), color: 16777215 });
      g.tint = kit.color(si + j);
      return g;
    });
    let pulse = null;
    if (!oneShot) {
      pulse = kit.graphics();
      pulse.circle(0, 0, radius).stroke({ width: line2 * 0.6, color: 16777215 });
      pulse.tint = kit.color(si + 1);
    }
    return { site, rings: rings2, pulse };
  });
  const p = newPos3();
  return (time) => {
    const anchors = kit.anchors(time);
    for (const u of units) {
      kit.pos(u.site, anchors, p);
      const e = time - u.site.start;
      u.rings.forEach((g, j) => {
        const local = e - j * 0.09;
        const x = kit.exit(time, j * 0.05);
        if (local < 0 || x >= 1) {
          g.visible = false;
          return;
        }
        let scale;
        let alpha;
        if (oneShot) {
          const k = clamp017(local / 0.8);
          scale = 0.3 + 1.1 * easeOutExpo2(k);
          alpha = (1 - k) ** 1.5;
        } else {
          scale = lerp3(0.2, 1, easeOutBack(local / 0.55, 2.4)) * (1 + 0.025 * Math.sin(TAU2 * (time * 0.5 + j / 3)));
          alpha = clamp017(local / 0.08);
          scale *= 1 - easeInBack(x, 2);
          alpha *= 1 - x;
        }
        g.visible = alpha > 5e-3 && scale > 1e-3;
        g.position.set(p.x, p.y);
        g.scale.set(Math.max(1e-3, scale));
        g.alpha = alpha * p.alpha;
      });
      if (u.pulse) {
        const q = fract2((e - 0.6) / 1.8);
        const x = kit.exit(time);
        u.pulse.visible = e > 0.6 && x < 1;
        u.pulse.position.set(p.x, p.y);
        u.pulse.scale.set(1 + 0.55 * easeOutCubic3(q));
        u.pulse.alpha = 0.55 * (1 - q) ** 2 * (1 - x) * p.alpha;
      }
    }
  };
};
var spokesOrnament = (kit) => {
  const oneShot = kit.spec.placement === "glyphs";
  const big = kit.spec.placement === "behind" || kit.spec.placement === "around" || kit.spec.placement === "screen";
  const pad = kit.size * 0.45;
  const units = kit.sites("single", 6).map((site, si) => {
    const n = oneShot ? 8 : kit.count(big ? 28 : 10, 6);
    const spokes = Array.from({ length: n }, (_, i) => {
      const angle = TAU2 * i / n + (kit.rng() - 0.5) * (TAU2 / n) * 0.7;
      const cos = Math.cos(angle);
      const sin = Math.sin(angle);
      const inner = big ? 1 / Math.sqrt((cos / (site.w + pad)) ** 2 + (sin / (site.h + pad)) ** 2) : site.w * 1.1;
      const sprite = kit.sprite("streak");
      sprite.rotation = angle + Math.PI / 2;
      sprite.tint = kit.color(si + i);
      return {
        sprite,
        cos,
        sin,
        inner,
        length: kit.size * (oneShot ? 0.5 + kit.rng() * 0.5 : 0.7 + kit.rng() * 1.7),
        thick: Math.max(1.2, kit.size * (0.035 + kit.rng() * 0.05)),
        delay: i % 6 * 0.015,
        salt: si * 97 + i
      };
    });
    return { site, spokes };
  });
  const p = newPos3();
  return (time) => {
    const anchors = kit.anchors(time);
    const beat = Math.floor(time * 12);
    const x = kit.exit(time);
    for (const u of units) {
      kit.pos(u.site, anchors, p);
      const e = time - u.site.start;
      for (const s of u.spokes) {
        const local = e - s.delay;
        if (local < 0 || x >= 1) {
          s.sprite.visible = false;
          continue;
        }
        const grow = easeOutExpo2(local / 0.25);
        const jitter = 0.72 + 0.45 * hash01(beat, s.salt);
        let length = s.length * grow * jitter * (1 - x);
        let push = kit.size * 2.5 * easeInCubic(x);
        let alpha = (0.55 + 0.45 * hash01(beat + 7, s.salt)) * p.alpha;
        if (oneShot) {
          const k = clamp017((local - 0.3) / 0.35);
          push += kit.size * 0.8 * easeOutCubic3(k);
          length *= 1 - k;
          alpha *= 1 - k;
        }
        const r = s.inner + push + length / 2;
        s.sprite.visible = length > 0.5 && alpha > 0.01;
        s.sprite.position.set(p.x + s.cos * r, p.y + s.sin * r);
        s.sprite.width = s.thick * (1 - x * 0.5);
        s.sprite.height = length;
        s.sprite.alpha = alpha;
      }
    }
  };
};
var orbitOrnament = (kit) => {
  const big = kit.spec.placement === "behind" || kit.spec.placement === "around" || kit.spec.placement === "screen";
  const tilt = -0.18;
  const units = kit.sites("single", 4).map((site, si) => {
    const rx = big ? site.w + kit.size * 0.5 : site.w * 1.5;
    const ry = big ? site.h + kit.size * 0.6 : site.h * 0.8;
    const trains = big ? Math.max(2, Math.min(6, kit.count(4, 2))) : 2;
    const cars = big ? 5 : 3;
    const rings2 = [
      { omega: 0.55, reach: 1, trains },
      { omega: -0.85, reach: 1.2, trains: Math.max(1, trains - 1) }
    ];
    const paths = rings2.map((ring, r) => {
      const g = kit.graphics();
      g.ellipse(0, 0, rx * ring.reach, ry * ring.reach).stroke({ width: Math.max(1, kit.size * 0.02), color: 16777215 });
      g.rotation = tilt;
      g.tint = kit.color(si + r);
      return { g, delay: r * 0.12 };
    });
    const dots = rings2.flatMap((ring, r) => Array.from({ length: ring.trains * cars }, (_, index) => {
      const train = Math.floor(index / cars);
      const car = index % cars;
      const leader = car === 0;
      const sprite = kit.sprite(leader ? "star4" : "dot");
      sprite.tint = kit.color(si + r + train);
      return {
        sprite,
        theta: TAU2 * train / ring.trains + r * 0.5 - Math.sign(ring.omega) * car * 0.11,
        omega: ring.omega,
        rx: rx * ring.reach,
        ry: ry * ring.reach,
        size: kit.size * (leader ? 0.34 : 0.14 * (1 - car / (cars + 1))),
        delay: train * 0.06 + car * 0.03 + r * 0.12
      };
    }));
    return { site, dots, paths };
  });
  const p = newPos3();
  const cosT = Math.cos(tilt);
  const sinT = Math.sin(tilt);
  return (time) => {
    const anchors = kit.anchors(time);
    for (const u of units) {
      kit.pos(u.site, anchors, p);
      const e = time - u.site.start;
      for (const path2 of u.paths) {
        const local = e - path2.delay;
        const x = kit.exit(time);
        path2.g.visible = local >= 0 && x < 1;
        if (!path2.g.visible) continue;
        path2.g.position.set(p.x, p.y);
        path2.g.scale.set(Math.max(1e-3, easeOutBack(local / 0.5, 1.8) * (1 + 1.2 * easeInCubic(x))));
        path2.g.alpha = 0.3 * clamp017(local / 0.1) * (1 - x) * p.alpha;
      }
      u.dots.forEach((d, i) => {
        const local = e - d.delay;
        const x = kit.exit(time, i % 8 * 0.02);
        if (local < 0 || x >= 1) {
          d.sprite.visible = false;
          return;
        }
        const reach = spring(local, 1.6, 5.5) * (1 + 1.2 * easeInCubic(x));
        const theta = d.theta + d.omega * time - Math.sign(d.omega) * 2.2 * (1 - easeOutCubic3(local / 0.9));
        const ox = Math.cos(theta) * d.rx * reach;
        const oy = Math.sin(theta) * d.ry * reach;
        const near = 0.5 + 0.5 * Math.sin(theta);
        d.sprite.visible = true;
        d.sprite.position.set(p.x + ox * cosT - oy * sinT, p.y + ox * sinT + oy * cosT);
        const s = d.size * (0.65 + 0.35 * near);
        d.sprite.width = s;
        d.sprite.height = s;
        d.sprite.rotation = theta;
        d.sprite.alpha = clamp017(local / 0.05) * (0.45 + 0.55 * near) * (1 - x) * p.alpha;
      });
    }
  };
};
var bracketsOrnament = (kit) => {
  const placement = kit.spec.placement;
  const thick = Math.max(2, kit.size * 0.08);
  const pad = kit.size * 0.4;
  const make = (a, b, rotation, color) => {
    const g = kit.graphics();
    g.moveTo(a, 0).lineTo(0, 0).lineTo(0, b).stroke({ width: thick, color: 16777215, cap: "square", join: "miter" });
    g.rotation = rotation;
    g.tint = color;
    return g;
  };
  const CORNERS = [[-1, -1, 0], [1, -1, Math.PI / 2], [1, 1, Math.PI], [-1, 1, Math.PI * 1.5]];
  if (placement === "glyphs" && kit.glyphs.length > 0) {
    const arm = kit.size * 0.28;
    const corners = CORNERS.map(([sx, sy, rot], k) => ({ g: make(arm, arm, rot, kit.color(k)), sx, sy }));
    const order = [...kit.glyphs].sort((p, q) => p.sungAt - q.sungAt);
    return (time) => {
      const x = kit.exit(time);
      let current = -1;
      for (let i = 0; i < order.length; i += 1) if (order[i].sungAt <= time) current = i;
      const visible = current >= 0 && time >= kit.start && x < 1;
      for (const c of corners) c.g.visible = visible;
      if (!visible) return;
      const anchors = kit.anchors(time);
      const cur = order[current];
      const prev = order[Math.max(0, current - 1)];
      const a = anchors[cur.index];
      const b = anchors[prev.index];
      const k = current === 0 ? 1 : easeOutBack((time - cur.sungAt) / 0.2, 1.8);
      const px = lerp3(b?.x ?? prev.x, a?.x ?? cur.x, k);
      const py = lerp3(b?.y ?? prev.y, a?.y ?? cur.y, k);
      const half = lerp3(b?.size ?? prev.size, a?.size ?? cur.size, k) * 0.62;
      const snap = 1 + 0.35 * Math.exp(-(time - cur.sungAt) / 0.08);
      for (const c of corners) {
        c.g.position.set(px + c.sx * half * snap * (1 + x), py + c.sy * half * snap * (1 + x));
        c.g.alpha = (1 - x) * (a?.alpha ?? 1);
      }
    };
  }
  let rw = kit.hw + pad;
  let rh = kit.hh + pad * 0.7;
  let cx = kit.cx;
  let cy = kit.cy;
  if (placement === "screen") {
    rw = kit.ctx.width * 0.42;
    rh = kit.ctx.height * 0.38;
    cx = 0;
    cy = 0;
  }
  let chosen = CORNERS;
  let armA = Math.min(rw * 0.35, kit.size * 0.9);
  let armB = armA;
  if (placement === "behind" || placement === "around" || placement === "line-start" || placement === "line-end") {
    chosen = placement === "line-start" ? [CORNERS[0]] : placement === "line-end" ? [CORNERS[2]] : [CORNERS[0], CORNERS[2]];
    armA = kit.vertical ? rw * 1.2 : kit.size * 0.55;
    armB = kit.vertical ? kit.size * 0.55 : rh * 1.2;
  }
  const pieces = chosen.map(([sx, sy, rot], k) => {
    const swap = k % 2 === 1 && chosen.length === 4;
    return { g: make(swap ? armB : armA, swap ? armA : armB, rot, kit.color(k)), sx, sy, delay: k * 0.06 };
  });
  return (time) => {
    const beat = Math.exp(-(time - kit.lastSung(time)) / 0.12);
    pieces.forEach((piece, k) => {
      const local = time - kit.start - piece.delay;
      const x = kit.exit(time, k * 0.04);
      if (local < 0 || x >= 1) {
        piece.g.visible = false;
        return;
      }
      let off = (1 - easeOutBack(local / 0.45, 2.6)) * kit.size * 1.4;
      off += kit.size * 0.06 * Math.sin(TAU2 * time * 0.7) - kit.size * 0.15 * beat;
      off += easeInCubic(x) * kit.size * 2;
      const flick = local < 0.12 ? Math.floor(local * 40) % 2 === 0 ? 1 : 0.25 : 1;
      piece.g.visible = true;
      piece.g.position.set(cx + piece.sx * (rw + off), cy + piece.sy * (rh + off));
      piece.g.alpha = flick * (1 - x);
    });
  };
};
var dashCircleOrnament = (kit) => {
  const oneShot = kit.spec.placement === "glyphs";
  const line2 = Math.max(1.5, kit.size * 0.05);
  const units = kit.sites("single", 6).map((site, si) => {
    const r1 = oneShot ? site.w * 1.35 : siteRadius(kit.spec.placement, site, kit.size * 0.6) * 1.05;
    const r2 = r1 * 0.84;
    const outer = kit.graphics();
    const dashes = r1 > kit.size * 2 ? 36 : 18;
    for (let k = 0; k < dashes; k += 1) {
      const a0 = k * TAU2 / dashes;
      const a1 = a0 + TAU2 / dashes * 0.55;
      outer.moveTo(Math.cos(a0) * r1, Math.sin(a0) * r1).arc(0, 0, r1, a0, a1);
    }
    outer.stroke({ width: line2, color: 16777215, cap: "round" });
    outer.tint = kit.color(si);
    const inner = kit.graphics();
    const dots = dashes * 2;
    for (let k = 0; k < dots; k += 1) {
      const a = k * TAU2 / dots;
      inner.circle(Math.cos(a) * r2, Math.sin(a) * r2, line2 * 0.7);
    }
    inner.fill({ color: 16777215 });
    inner.tint = kit.color(si + 1);
    return { site, outer, inner };
  });
  const p = newPos3();
  return (time) => {
    const anchors = kit.anchors(time);
    const x = kit.exit(time);
    for (const u of units) {
      kit.pos(u.site, anchors, p);
      const local = time - u.site.start;
      const fadeOut = oneShot ? clamp017((local - 1) / 0.4) : 0;
      const visible = local >= 0 && x < 1 && fadeOut < 1;
      u.outer.visible = visible;
      u.inner.visible = visible;
      if (!visible) continue;
      const scale = lerp3(0.55, 1, easeOutBack(local / 0.5, 2)) * (1 + 0.3 * easeInCubic(x));
      const spinIn = (1 - easeOutCubic3(local / 0.9)) * Math.PI * 1.2;
      const alpha = clamp017(local / 0.1) * (1 - x) * (1 - fadeOut) * p.alpha;
      u.outer.position.set(p.x, p.y);
      u.outer.scale.set(scale);
      u.outer.rotation = 0.35 * time + spinIn + x * x * 3;
      u.outer.alpha = alpha;
      u.inner.position.set(p.x, p.y);
      u.inner.scale.set(scale);
      u.inner.rotation = -beatSteps((time - u.site.start) / 0.5) * (Math.PI / 18) - spinIn;
      u.inner.alpha = alpha * 0.85;
    }
  };
};
var squaresOrnament = (kit) => {
  const big = kit.spec.placement === "behind" || kit.spec.placement === "around" || kit.spec.placement === "screen";
  const oneShot = kit.spec.placement === "glyphs";
  const layers = Math.min(4, Math.max(2, kit.count(3.2, 2)));
  const line2 = Math.max(1.5, kit.size * 0.05);
  const pad = kit.size * 0.35;
  const units = kit.sites("single", 5).map((site, si) => {
    const squares = Array.from({ length: layers }, (_, j) => {
      const g = kit.graphics();
      const w = big ? site.w + pad * (j + 1) : site.w * (1.1 + 0.3 * j);
      const h = big ? site.h + pad * (j + 1) : w;
      g.rect(-w, -h, w * 2, h * 2).stroke({ width: line2 * (j === 0 ? 1.5 : 1), color: 16777215, join: "miter" });
      g.tint = kit.color(si + j);
      return { g, dir: j % 2 === 0 ? 1 : -1, delay: j * 0.07, offset: j * 0.25 };
    });
    return { site, squares };
  });
  const p = newPos3();
  return (time) => {
    const anchors = kit.anchors(time);
    for (const u of units) {
      kit.pos(u.site, anchors, p);
      u.squares.forEach((s, j) => {
        const local = time - u.site.start - s.delay;
        const x = Math.max(kit.exit(time, (layers - 1 - j) * 0.05), oneShot ? clamp017((local - 1.1) / 0.4) : 0);
        if (local < 0 || x >= 1) {
          s.g.visible = false;
          return;
        }
        const beats = local / 1 + s.offset;
        let rotation;
        if (big) {
          const phase = Math.floor(beats) % 2 === 0 ? 1 : -1;
          rotation = s.dir * 0.09 * lerp3(-phase, phase, easeOutBack(fract2(beats) / 0.35, 2));
        } else {
          rotation = s.dir * beatSteps(beats) * (Math.PI / 4);
        }
        const scale = easeOutBack(local / 0.4, 2.2) * (1 - easeInBack(x, 2));
        s.g.visible = Math.abs(scale) > 1e-3;
        s.g.position.set(p.x, p.y);
        s.g.rotation = rotation;
        s.g.scale.set(Math.max(1e-3, scale));
        s.g.alpha = clamp017(local / 0.06) * (1 - x) * p.alpha;
      });
    }
  };
};
var raysOrnament = (kit) => {
  const oneShot = kit.spec.placement === "glyphs";
  const faint = kit.spec.placement === "behind" || kit.spec.placement === "screen";
  const units = kit.sites("single", 3).map((site, si) => {
    const radius = kit.spec.placement === "screen" ? Math.hypot(kit.ctx.width, kit.ctx.height) * 0.6 : kit.spec.placement === "behind" || kit.spec.placement === "around" ? Math.hypot(site.w, site.h) * 1.7 : site.w * 2.4;
    const wedges = oneShot ? 8 : Math.max(6, kit.count(12, 6));
    const g = kit.graphics();
    for (let k = 0; k < wedges; k += 1) {
      const a0 = k * TAU2 / wedges;
      const a1 = a0 + TAU2 / wedges * 0.5;
      g.moveTo(0, 0).lineTo(Math.cos(a0) * radius, Math.sin(a0) * radius).lineTo(Math.cos(a1) * radius, Math.sin(a1) * radius).closePath();
    }
    g.fill({ color: 16777215 });
    g.tint = kit.color(si);
    return { site, g, dir: si % 2 === 0 ? 1 : -1 };
  });
  const p = newPos3();
  const baseAlpha = faint ? 0.26 : 0.45;
  return (time) => {
    const anchors = kit.anchors(time);
    const x = kit.exit(time);
    const tick = Math.exp(-(time - kit.lastSung(time)) / 0.15);
    for (const u of units) {
      kit.pos(u.site, anchors, p);
      const local = time - u.site.start;
      if (local < 0 || x >= 1 || oneShot && local > 1.2) {
        u.g.visible = false;
        continue;
      }
      let scale = easeOutBack(local / 0.6, 1.6) * (1 + 0.03 * Math.sin(TAU2 * time * 0.8) + 0.04 * tick) * (1 + 0.25 * x);
      let alpha = baseAlpha * clamp017(local / 0.1) * (1 - x);
      if (oneShot) {
        const k = clamp017((local - 0.5) / 0.7);
        alpha *= 1 - k;
        scale *= 1 + 0.3 * k;
      }
      u.g.visible = true;
      u.g.position.set(p.x, p.y);
      u.g.scale.set(Math.max(1e-3, scale));
      u.g.rotation = u.dir * (time * 0.12 - 0.8 * (1 - easeOutCubic3(local / 0.8)) + x * x * 1.5);
      u.g.alpha = alpha * p.alpha;
    }
  };
};
var STAMP_CHARS = ["\u82B1", "\u706B", "\u590F", "\u591C", "\u7A7A", "\u5149"];
var STAMP_FONT = '"Hiragino Mincho ProN", "Yu Mincho", "Noto Serif JP", "Noto Serif SC", "Songti SC", serif';
var stampOrnament = (kit) => {
  const placement = kit.spec.placement;
  const pad = kit.size * 0.6;
  let radius = kit.size * 0.72;
  let x0;
  let y0;
  let faint = false;
  const corner = Math.floor(kit.rng() * 4);
  const sx = corner === 0 || corner === 3 ? -1 : 1;
  const sy = corner < 2 ? -1 : 1;
  switch (placement) {
    case "behind":
      radius = Math.min(kit.hw, kit.hh) * 1.1 + kit.size * 0.3;
      x0 = kit.cx;
      y0 = kit.cy;
      faint = true;
      break;
    case "screen":
      x0 = sx * kit.ctx.width * 0.36;
      y0 = sy * kit.ctx.height * 0.32;
      radius = Math.min(kit.ctx.width, kit.ctx.height) * 0.08 * kit.spec.scale;
      break;
    case "line-start":
      x0 = kit.vertical ? kit.cx : kit.cx - kit.hw - pad - radius;
      y0 = kit.vertical ? kit.cy - kit.hh - pad - radius : kit.cy;
      break;
    case "line-end":
    case "glyphs":
      x0 = kit.vertical ? kit.cx : kit.cx + kit.hw + pad * 0.6 + radius;
      y0 = kit.vertical ? kit.cy + kit.hh + pad * 0.6 + radius : kit.cy + kit.hh * 0.4;
      break;
    default:
      x0 = kit.cx + sx * (kit.hw + radius * 0.6);
      y0 = kit.cy + sy * (kit.hh + radius * 0.5);
  }
  const holder = new kit.pixi.Container();
  kit.view.addChild(holder);
  holder.position.set(x0, y0);
  const frame2 = kit.graphics(holder);
  frame2.circle(0, 0, radius).stroke({ width: radius * 0.1, color: 16777215 });
  frame2.circle(0, 0, radius * 0.8).stroke({ width: radius * 0.035, color: 16777215 });
  const char = STAMP_CHARS[Math.floor(kit.rng() * STAMP_CHARS.length) % STAMP_CHARS.length];
  const text = new kit.pixi.Text({
    text: char,
    style: { fontFamily: STAMP_FONT, fontSize: Math.max(8, radius * 1.02), fontWeight: "900", fill: 16777215, align: "center" }
  });
  text.anchor.set(0.5, 0.54);
  holder.addChild(text);
  holder.tint = kit.color(0);
  const shock = kit.sprite("ring");
  shock.tint = kit.color(1);
  const tilt = (kit.rng() - 0.5) * 0.3;
  const slam = 0.18;
  return (time) => {
    const local = time - kit.start;
    const x = kit.exit(time);
    if (local < 0 || x >= 1) {
      holder.visible = false;
      shock.visible = false;
      return;
    }
    holder.visible = true;
    let scale;
    let rotation;
    if (local < slam) {
      const k2 = easeInCubic(local / slam);
      scale = lerp3(2.4, 1, k2);
      rotation = lerp3(-0.5, tilt, k2);
    } else {
      const after = local - slam;
      scale = 1 + 0.14 * Math.exp(-after * 9) * Math.cos(after * 38);
      rotation = tilt + 0.02 * Math.sin(time * 0.6);
    }
    scale *= 1 - easeInBack(x, 2.4);
    holder.scale.set(Math.max(1e-3, scale));
    holder.rotation = rotation;
    holder.alpha = clamp017(local / 0.06) * (faint ? 0.3 : 1) * (x > 0.6 ? Math.floor(x * 20) % 2 === 0 ? 1 : 0.3 : 1);
    const impact = local - slam;
    const k = clamp017(impact / 0.45);
    shock.visible = impact >= 0 && k < 1;
    if (shock.visible) {
      const size = radius * 2 * (1 + 0.9 * easeOutCubic3(k));
      shock.position.set(x0, y0);
      shock.width = size;
      shock.height = size;
      shock.alpha = (1 - k) ** 2 * (faint ? 0.3 : 0.8);
    }
  };
};
var halftoneOrnament = (kit) => {
  const placement = kit.spec.placement;
  const perSite = placement === "glyphs" ? 25 : placement === "corners" ? 36 : kit.count(170, 40);
  const units = kit.sites("single", 6).map((site, si) => {
    let w = site.w;
    let h = site.h;
    if (placement === "around") {
      w = w * 1.2 + kit.size * 0.4;
      h = h * 1.35 + kit.size * 0.6;
    } else if (placement === "behind") {
      w = w * 1.15 + kit.size * 0.3;
      h = h * 1.6 + kit.size * 0.4;
    } else if (placement === "glyphs") {
      w *= 1.4;
      h *= 1.4;
    }
    const spacing = Math.max(kit.size * 0.18, Math.sqrt(4 * w * h / Math.min(260, perSite)));
    const cols = Math.max(2, Math.round(2 * w / spacing));
    const rows = Math.max(2, Math.round(2 * h / spacing));
    const dirA = Math.floor(kit.rng() * 4) * Math.PI / 2 + Math.PI / 4;
    const dx = Math.cos(dirA);
    const dy = Math.sin(dirA);
    const dots = [];
    for (let r = 0; r < rows; r += 1) {
      for (let c = 0; c < cols; c += 1) {
        const ox = (c - (cols - 1) / 2) * spacing + (r % 2 === 0 ? 0 : spacing * 0.5);
        const oy = (r - (rows - 1) / 2) * spacing;
        const proj = clamp017(0.5 + (ox * dx + oy * dy) / (2 * Math.hypot(w, h)) * 1.4);
        const sprite = kit.sprite("dot");
        sprite.tint = kit.color(si);
        dots.push({ sprite, ox, oy, proj });
      }
    }
    return { site, dots, spacing };
  });
  const p = newPos3();
  return (time) => {
    const anchors = kit.anchors(time);
    const x = kit.exit(time);
    for (const u of units) {
      kit.pos(u.site, anchors, p);
      const local = time - u.site.start;
      for (const d of u.dots) {
        const reveal = local - d.proj * 0.55;
        const leave2 = x * 1.6 - (1 - d.proj) * 0.6;
        const pop = easeOutBack(reveal / 0.22, 2.5) * (1 - clamp017(leave2 / 0.4));
        const wave2 = 0.22 * Math.sin(TAU2 * (d.proj * 1.5 - time * 0.4));
        const value = clamp017(1 - d.proj * 0.9 + wave2);
        const size = u.spacing * 0.92 * value * pop;
        d.sprite.visible = size > 0.4 && reveal > 0;
        if (!d.sprite.visible) continue;
        d.sprite.position.set(p.x + d.ox, p.y + d.oy);
        d.sprite.width = size;
        d.sprite.height = size;
        d.sprite.alpha = 0.75 * p.alpha;
      }
    }
  };
};

// folia:src/components/visualizer/hanabi/mg/ornaments.ts
var ORNAMENT_BUILDERS = {
  ring: ringOrnament,
  spokes: spokesOrnament,
  sparkle: sparkleOrnament,
  orbit: orbitOrnament,
  chevrons: chevronsOrnament,
  brackets: bracketsOrnament,
  cross: crossOrnament,
  zigzag: zigzagOrnament,
  wave: waveOrnament,
  halftone: halftoneOrnament,
  confetti: confettiOrnament,
  shards: shardsOrnament,
  "dash-circle": dashCircleOrnament,
  squares: squaresOrnament,
  streaks: streaksOrnament,
  petals: petalsOrnament,
  stamp: stampOrnament,
  rays: raysOrnament,
  underline: underlineOrnament,
  "dots-line": dotsLineOrnament,
  glints: glintsOrnament
};
var createOrnament = (spec, context) => {
  const kit = createKit(spec, context);
  const empty = context.amount <= 0;
  const draw = empty ? null : ORNAMENT_BUILDERS[spec.kind](kit);
  const firstSung = kit.glyphs.reduce((min, glyph) => Math.min(min, glyph.sungAt), Number.POSITIVE_INFINITY);
  const from = Math.min(kit.start, firstSung) - 0.05;
  const update = (time) => {
    const visible = draw !== null && time >= from && time <= kit.end;
    kit.view.visible = visible;
    if (visible) draw(time);
  };
  return {
    view: kit.view,
    update,
    destroy: () => kit.view.destroy({ children: true, context: true })
  };
};

// folia:src/components/visualizer/hanabi/scene.ts
var SHOT_PARTICLES = 750;
var PREPARE_AHEAD = 1.5;
var MAX_SUNG_BURSTS = 28;
var MAX_DISSOLVE_BURSTS = 24;
var DISSOLVE_SPARK = { kind: "botan", count: 10, radius: 0.03, duration: 0.65, colors: [0, 1, 2], trail: 0.25, twinkle: 0.6 };
var BRIDGE_KINDS = ["mine", "senrin", "kiku", "botan", "ring", "crossette", "willow-ring", "strobe"];
var MOTION = { calm: 0.6, normal: 1, chaotic: 1.4 };
var toShot = (view, x, y) => {
  const px = (x - view.pivot.x) * view.scale.x;
  const py = (y - view.pivot.y) * view.scale.y;
  const cos = Math.cos(view.rotation);
  const sin = Math.sin(view.rotation);
  return { x: view.position.x + px * cos - py * sin, y: view.position.y + px * sin + py * cos };
};
var sungRange = (line2) => {
  const words = (line2?.words ?? []).filter((word) => word.text.trim().length > 0);
  if (words.length === 0) return { first: line2?.startTime ?? null, last: line2?.endTime ?? null };
  return { first: words[0].startTime, last: Math.max(...words.map((word) => word.endTime)) };
};
var thin = (items, max) => {
  if (items.length <= max) return items;
  const step = items.length / max;
  return Array.from({ length: max }, (_, k) => items[Math.floor(k * step)]);
};
var createHanabiScene = (pixi, options) => {
  const { width, height, tuning, theme, textures } = options;
  const unit = Math.min(width, height);
  const motion = MOTION[theme.animationIntensity] ?? 1;
  const fontScale = (options.fontScale ?? 1) * (globalThis.tfnLyricScale ?? 1);
  const graphicsOn = !tuning.textOnly;
  const keywordColor = keywordColorOf(theme);
  const paletteCache = /* @__PURE__ */ new Map();
  const paletteOf = (profile) => {
    let palette = paletteCache.get(profile.palette);
    if (!palette) {
      palette = resolveHanabiPalette(profile.palette, theme, tuning.colorMode);
      paletteCache.set(profile.palette, palette);
    }
    return palette;
  };
  const timelineShots = options.shots.map((shot) => {
    const sung = sungRange(shot.line);
    return {
      startTime: shot.startTime,
      endTime: shot.endTime,
      firstSung: shot.isBridge ? null : sung.first,
      lastSungEnd: shot.isBridge ? null : sung.last,
      isBridge: shot.isBridge,
      camera: shot.profile.camera
    };
  });
  const { angles: spinAngles, drift: spinDrift } = planSpin(options.shots.map((shot) => shot.endTime - shot.startTime), {
    amount: graphicsOn ? Math.max(0, tuning.spin) : 0,
    direction: options.spinDirection ?? 1,
    random: createRng2(`${options.seed}:spin`)
  });
  const timeline = buildTimeline(timelineShots, {
    unitStart: options.startTime,
    unitEnd: options.endTime,
    height,
    // 借给别的包时（只画字）字要停在宿主的文字区里，不随世界上漂。
    riseSpeed: graphicsOn ? Math.max(0, tuning.riseSpeed) : 0,
    motion: motion * Math.max(0, tuning.textMotion),
    exitStart: options.exitStart ?? null,
    spinAngles,
    spinDrift
  });
  const view = new pixi.Container();
  const stage2 = new pixi.Container();
  const world = new pixi.Container();
  const spin = new pixi.Container();
  spin.pivot.set(width / 2, height / 2);
  spin.position.set(width / 2, height / 2);
  spin.addChild(world);
  view.addChild(stage2);
  const lead = options.shots[0];
  const distantRate = options.shots.reduce((sum, shot) => sum + { quiet: 0.08, neutral: 0.2, loud: 0.35 }[shot.profile.mood], 0) / Math.max(options.shots.length, 1);
  const ambient = graphicsOn && tuning.ambient > 0 && lead ? createAmbient({
    pixi,
    textures,
    width,
    height,
    seed: `${options.seed}:ambient`,
    palette: paletteOf(lead.profile),
    startTime: options.startTime,
    endTime: options.endTime,
    density: Math.min(2, tuning.ambient) * (HANABI_QUALITY_PROFILES[tuning.renderQuality] ?? HANABI_QUALITY_PROFILES.full).ambientScale,
    distantBursts: distantRate
  }) : null;
  const collageOn = graphicsOn && tuning.collage > 0;
  const motifs = options.motifs && options.motifs.length > 0 ? options.motifs : ["HANABI", "\u82B1\u706B"];
  const collageCache = collageOn ? createCollageTextureCache(pixi, options.resolution, resolveThemeFontStack(theme)) : null;
  const unitCollage = collageCache && lead ? createUnitCollage(pixi, {
    width,
    height,
    resolution: options.resolution,
    seed: options.seed,
    cache: collageCache,
    paper: paletteOf(lead.profile).paper,
    amount: Math.min(2, tuning.collage),
    startTime: options.startTime
  }) : null;
  if (ambient) stage2.addChild(ambient.back);
  if (unitCollage) stage2.addChild(unitCollage.back);
  stage2.addChild(spin);
  if (ambient) stage2.addChild(ambient.front);
  if (unitCollage) stage2.addChild(unitCollage.front);
  const glow = graphicsOn && tuning.glow > 0 ? createHanabiGlow(pixi, Math.min(2, tuning.glow), resolveHanabiGlowQuality(width, height, options.resolution, tuning.renderQuality)) : null;
  const screenToShot = (built2, sx, sy, time) => ({
    x: sx - built2.region.cx * width,
    y: sy - (built2.region.cy * height + built2.timing.worldY + timeline.rise(time))
  });
  let previousRecipe = null;
  const built = options.shots.map((shot, index) => {
    const { profile } = shot;
    const timing = timeline.shots[index];
    const palette = paletteOf(profile);
    const region = profile.region;
    const container = new pixi.Container();
    container.position.set(region.cx * width, region.cy * height + timing.worldY);
    const fireworksHolder = new pixi.Container();
    const ornBack = new pixi.Container();
    const ornFront = new pixi.Container();
    const collageBack = new pixi.Container();
    const collageFront = new pixi.Container();
    const mid = new pixi.Container();
    container.addChild(fireworksHolder, ornBack, collageBack);
    const text = shot.line && !shot.isBridge ? createHanabiText({
      pixi,
      width,
      height,
      resolution: options.resolution,
      theme,
      line: shot.line,
      regionWidth: region.w * width,
      regionHeight: region.h * height,
      spec: { ...profile.text, heroSize: profile.text.heroSize * fontScale },
      palette,
      seed: `${options.seed}:${shot.id}:text`,
      enterAt: timing.enterAt,
      exitAt: timing.exitAt,
      exitDuration: timing.exitDuration,
      motion: Math.max(0, tuning.textMotion),
      blockOpacity: Math.min(1, Math.max(0, tuning.blockOpacity)),
      keywordColor
    }) : null;
    if (text) {
      container.addChild(text.view);
      const glyphParent = text.glyphs.parent;
      if (glyphParent) glyphParent.addChildAt(mid, glyphParent.getChildIndex(text.glyphs));
      else container.addChild(mid);
    } else {
      container.addChild(mid);
    }
    container.addChild(ornFront, collageFront);
    const holder = new pixi.Container();
    holder.pivot.set(width / 2, height / 2 + timing.worldY);
    holder.position.set(width / 2, height / 2 + timing.worldY);
    holder.rotation = -timing.spin;
    holder.addChild(container);
    world.addChild(holder);
    const { bursts, launches, mains } = graphicsOn ? planShotEvents({ shot, index, timing, palette, text, region, seed: options.seed, screenToShot, width, height, unit, tuning }) : { bursts: [], launches: [], mains: [] };
    const burstEnd = Math.max(...bursts.map((event) => event.at + event.spec.duration), -Infinity);
    const launchEnd2 = Math.max(...launches.map((event) => event.at + event.duration + 0.7), -Infinity);
    const regionBounds = { x: -region.w * width / 2, y: -region.h * height / 2, width: region.w * width, height: region.h * height };
    const collage = collageOn ? planShotCollage({
      seed: `${options.seed}:${shot.id}`,
      family: profile.family,
      mood: profile.mood,
      isBridge: shot.isBridge,
      block: profile.text.block,
      shotNumber: index,
      bounds: text?.bounds ?? regionBounds,
      screen: { x: -region.cx * width, y: -region.cy * height, width, height },
      screenAt: (time) => ({ ...screenToShot({ region, timing }, 0, 0, time), width, height }),
      unit,
      palette,
      enterAt: timing.enterAt,
      exitAt: timing.exitAt,
      exitDuration: timing.exitDuration,
      start: timing.start,
      end: timing.end,
      keyword: pickCollageKeyword(shot.line),
      motifs,
      bursts: mains.map((event) => ({
        x: event.x,
        y: event.y,
        at: event.at,
        kind: event.spec.kind,
        main: true,
        radius: event.spec.radius * unit * event.scale
      })),
      launches,
      amount: Math.min(2, tuning.collage),
      previous: previousRecipe,
      opening: index === 0 ? options.opening ?? null : null,
      icons: options.icons
    }) : { recipe: null, items: [] };
    previousRecipe = collage.recipe;
    const collageEnd = Math.max(...collage.items.map((item) => item.kind === "pop" || item.kind === "floater" ? item.at + item.duration : item.kind === "whoosh" ? item.at + item.duration + 0.55 : item.exitAt + item.exitDuration), -Infinity);
    return {
      shot,
      timing,
      palette,
      container,
      fireworksHolder,
      ornBack,
      ornFront,
      collageBack,
      collageFront,
      collage,
      mid,
      text,
      bursts,
      launches,
      lifeStart: Math.min(timing.launchAt, timing.enterAt) - 0.25,
      lifeEnd: Math.max(timing.exitAt + timing.exitDuration + 0.3, burstEnd + 0.05, launchEnd2, collageEnd + 0.05),
      rig: null
    };
  });
  const buildRig = (item) => {
    if (!graphicsOn) return { fireworks: null, ornaments: [], collage: null };
    const fireworks = createFireworks(pixi, textures, {
      width,
      height,
      palette: item.palette,
      amount: Math.max(0, tuning.sparkAmount),
      maxParticles: SHOT_PARTICLES
    });
    item.fireworksHolder.addChild(fireworks.view);
    if (glow) item.fireworksHolder.filters = [glow];
    const region = item.shot.profile.region;
    const bounds = item.text?.bounds ?? { x: -region.w * width / 2, y: -region.h * height / 2, width: region.w * width, height: region.h * height };
    const text = item.text;
    const anchorsAt = text ? (time) => text.anchors(time) : () => [];
    const ornaments = tuning.ornamentAmount > 0 ? item.shot.profile.ornaments.map((spec, k) => {
      const ornament = createOrnament(spec, {
        pixi,
        textures,
        width,
        height,
        seed: `${options.seed}:${item.shot.id}:ornament${k}`,
        palette: item.palette,
        bounds,
        anchorsAt,
        enterAt: item.timing.enterAt,
        exitAt: item.timing.exitAt,
        exitDuration: item.timing.exitDuration,
        amount: Math.min(2, tuning.ornamentAmount)
      });
      (spec.layer === "front" ? item.ornFront : item.ornBack).addChild(ornament.view);
      return ornament;
    }) : [];
    let collage = null;
    if (collageCache && item.collage.items.length > 0) {
      collage = createShotCollage(pixi, item.collage, collageCache, textures);
      item.collageBack.addChild(collage.back);
      item.collageFront.addChild(collage.front);
    }
    return { fireworks, ornaments, collage };
  };
  const releaseRig = (item) => {
    if (!item.rig) return;
    item.fireworksHolder.filters = [];
    item.rig.fireworks?.destroy();
    item.rig.ornaments.forEach((ornament) => ornament.destroy());
    item.rig.collage?.destroy();
    item.rig = null;
  };
  let layers = { graphics: true, text: true, mid: true };
  const applyLayers = () => {
    if (ambient) {
      ambient.back.renderable = layers.graphics;
      ambient.front.renderable = layers.graphics;
    }
    if (unitCollage) {
      unitCollage.back.renderable = layers.graphics;
      unitCollage.front.renderable = layers.graphics;
    }
    for (const item of built) {
      item.fireworksHolder.renderable = layers.graphics;
      item.ornBack.renderable = layers.graphics;
      item.ornFront.renderable = layers.graphics;
      item.collageBack.renderable = layers.graphics;
      item.collageFront.renderable = layers.graphics;
      item.mid.renderable = layers.mid;
      if (item.text) {
        const shown = layers.text && !item.shot.textHidden;
        item.text.blocks.renderable = shown;
        item.text.glyphs.renderable = shown;
      }
    }
  };
  applyLayers();
  const rest = { x: width / 2, y: height / 2, pivotX: width / 2, pivotY: height / 2, scale: 1, rotation: 0 };
  const camera = (time) => {
    const offset = timeline.camera(time);
    return { ...rest, x: rest.x + offset.dx, y: rest.y + offset.dy, scale: offset.scale, rotation: offset.rotation };
  };
  const activeBursts = [];
  const activeLaunches = [];
  const beatCache = /* @__PURE__ */ new Map();
  let beatCacheEvents = null;
  let beatCacheStrength = -1;
  let beatCacheScale = -1;
  const beatBursts = built.map(() => []);
  const beatLaunches = built.map(() => []);
  const placeBeat = (event, beats) => {
    const key = Math.round(event.t * 1e3);
    if (beatCache.has(key)) return beatCache.get(key);
    let placed = null;
    const shell = resolveHanabiBeatShell(event, options.seed, beats.strength, beats.trackScale);
    const shot = timeline.shotAt(event.t);
    const item = built[shot];
    if (shell && item && event.t >= options.startTime && event.t <= options.endTime) {
      const located = { region: item.shot.profile.region, timing: item.timing };
      const p = screenToShot(located, shell.sx * width, shell.sy * height, event.t);
      const burst2 = { x: p.x, y: p.y, at: event.t, spec: shell.spec, seed: shell.seed, scale: 1 };
      let launch2 = null;
      if (shell.launch && tuning.launches) {
        const at = event.t - LAUNCH_DURATION;
        const bottom = screenToShot(located, shell.sx * width, height * 1.03, at);
        launch2 = { fromX: p.x, fromY: Math.max(bottom.y, p.y + height * 0.2), toX: p.x, toY: p.y, at, duration: LAUNCH_DURATION, color: item.palette.glow, seed: `${shell.seed}:launch` };
      }
      placed = { shot, burst: burst2, launch: launch2 };
    }
    beatCache.set(key, placed);
    return placed;
  };
  const collectBeats = (time, beats) => {
    beatBursts.forEach((list) => {
      list.length = 0;
    });
    beatLaunches.forEach((list) => {
      list.length = 0;
    });
    if (!graphicsOn || !beats || beats.strength <= 0 || beats.events.length === 0) return;
    if (beats.events !== beatCacheEvents || beats.strength !== beatCacheStrength || beats.trackScale !== beatCacheScale) {
      beatCache.clear();
      beatCacheEvents = beats.events;
      beatCacheStrength = beats.strength;
      beatCacheScale = beats.trackScale;
    }
    const until = time + LAUNCH_DURATION;
    for (let index = firstBeatAtOrAfter(beats.events, time - HANABI_BEAT_SHELL_LIFE); index < beats.events.length; index += 1) {
      const event = beats.events[index];
      if (event.t > until) break;
      const placed = placeBeat(event, beats);
      if (!placed) continue;
      if (time >= placed.burst.at) beatBursts[placed.shot].push(placed.burst);
      if (placed.launch && time >= placed.launch.at) beatLaunches[placed.shot].push(placed.launch);
    }
  };
  const update = (time, beats) => {
    const transform = camera(time);
    stage2.pivot.set(transform.pivotX, transform.pivotY);
    stage2.position.set(transform.x, transform.y);
    stage2.scale.set(transform.scale);
    stage2.rotation = transform.rotation;
    const rise = timeline.rise(time);
    world.y = rise;
    spin.rotation = timeline.spin(time);
    ambient?.update(time, rise);
    unitCollage?.update(time, rise);
    collectBeats(time, beats);
    built.forEach((item, index) => {
      const visible = time >= item.lifeStart && time <= item.lifeEnd;
      item.container.visible = visible;
      if (!visible) {
        if (time < item.lifeStart - PREPARE_AHEAD || time > item.lifeEnd) releaseRig(item);
        return;
      }
      if (!item.rig) item.rig = buildRig(item);
      item.text?.update(time);
      if (item.rig.fireworks) {
        activeBursts.length = 0;
        activeLaunches.length = 0;
        for (const event of item.bursts) {
          if (event.at > time) break;
          if (time <= event.at + event.spec.duration + 0.1) activeBursts.push(event);
        }
        for (const event of item.launches) {
          if (event.at <= time && time <= event.at + event.duration + 0.7) activeLaunches.push(event);
        }
        for (const event of beatBursts[index]) activeBursts.push(event);
        for (const event of beatLaunches[index]) {
          if (time <= event.at + event.duration + 0.7) activeLaunches.push(event);
        }
        item.rig.fireworks.update(time, activeBursts, activeLaunches);
      }
      item.rig.ornaments.forEach((ornament) => ornament.update(time));
      item.rig.collage?.update(time);
    });
  };
  const prepare = (time) => {
    for (const item of built) {
      if (time > item.lifeEnd || time < item.lifeStart - PREPARE_AHEAD) continue;
      if (item.text?.prepare()) return true;
      if (!item.rig) {
        item.rig = buildRig(item);
        return true;
      }
    }
    return false;
  };
  const midLayer = (time) => built[timeline.shotAt(time)]?.mid ?? null;
  return {
    view,
    timeline,
    events: built.map((item) => ({ bursts: item.bursts, launches: item.launches })),
    midLayer,
    setTfnViewport: (current) => {
      const base = options.tfnInsets ?? { top: 0, bottom: 0 };
      for (const item of built) {
        const mapped = tfnProjectLyric(item.shot.profile.region.cy * height, height, base, current);
        item.container.y = mapped.y + item.timing.worldY;
        item.container.scale.set(mapped.scale);
      }
    },
    camera,
    rest,
    update,
    prepare,
    setLayerVisibility: (next) => {
      layers = { ...next };
      applyLayers();
    },
    destroy: () => {
      built.forEach((item) => {
        releaseRig(item);
        item.text?.destroy();
      });
      ambient?.destroy();
      unitCollage?.destroy();
      glow?.destroy();
      view.destroy({ children: true });
      collageCache?.destroy();
    }
  };
};
var planShotEvents = (input) => {
  const { shot, index, timing, palette, text, region, width, height, unit, tuning } = input;
  const { profile } = shot;
  const random = createRng2(`${input.seed}:${shot.id}:${index}:events`);
  const bursts = [];
  const launches = [];
  const locate = (sx, sy, time) => input.screenToShot({ region, timing }, sx, sy, time);
  const launchColor = palette.glow;
  const withLaunch = profile.launch && tuning.launches;
  const launchTo = (x, y, arrive, key) => {
    const at = arrive - LAUNCH_DURATION;
    const bottom = locate(0, height * 1.03, at).y;
    launches.push({
      fromX: x + (random() - 0.5) * width * 0.08,
      fromY: Math.max(bottom, y + height * 0.2),
      toX: x,
      toY: y,
      at,
      duration: LAUNCH_DURATION,
      color: launchColor,
      seed: `${input.seed}:${shot.id}:${key}:launch`
    });
  };
  const shape = (spec) => spec.kind === "ring" || spec.kind === "willow-ring" || spec.kind === "heart" || spec.kind === "star" ? { squash: spec.kind === "ring" ? 0.4 + random() * 0.5 : 1, rotation: (random() - 0.5) * 0.6 } : {};
  if (shot.isBridge) {
    const from = timing.start + 0.15;
    const to = timing.end - 0.3;
    const duration = Math.max(0, to - from);
    const count = Math.max(1, Math.min(10, Math.round(duration / 0.75)));
    const kinds = profile.burst ? [profile.burst.kind, ...BRIDGE_KINDS] : BRIDGE_KINDS;
    for (let k = 0; k < count; k += 1) {
      const at = from + (count === 1 ? 0 : k / (count - 1) * duration * 0.85) + random() * 0.12;
      const kind = kinds[Math.floor(random() * kinds.length)];
      const spec = burstPreset(kind, [k % 5, (k + 1) % 5, (k + 2) % 5]);
      if (kind === "mine") {
        const p2 = locate(width * (0.2 + random() * 0.6), height * 0.94, at);
        bursts.push({ x: p2.x, y: p2.y, at, spec, seed: `${input.seed}:${shot.id}:b${k}`, scale: 0.8 + random() * 0.3 });
        continue;
      }
      const p = locate(width * (0.15 + random() * 0.7), height * (0.14 + random() * 0.34), at);
      bursts.push({ x: p.x, y: p.y, at, spec, seed: `${input.seed}:${shot.id}:b${k}`, scale: 0.55 + random() * 0.4, ...shape(spec) });
      if (tuning.launches) launchTo(p.x, p.y, at, `b${k}`);
    }
    bursts.sort((a, b) => a.at - b.at);
    return { bursts, launches, mains: [...bursts] };
  }
  const bounds = text?.bounds ?? { x: -region.w * width / 2, y: -region.h * height / 2, width: region.w * width, height: region.h * height };
  const centerX = bounds.x + bounds.width / 2;
  const centerY = bounds.y + bounds.height / 2;
  const mains = [];
  const main = profile.burst;
  if (main) {
    const radius = main.radius * unit;
    const at = timing.enterAt;
    const key = `${input.seed}:${shot.id}:main`;
    const minY = height * 0.12 - region.cy * height;
    const maxX = width * 0.42;
    const points = [];
    if (main.kind === "mine") {
      const sx = profile.burstAt === "sides" ? [0.25, 0.75] : [0.3 + random() * 0.4];
      sx.forEach((x, k) => points.push({ x: x * width - region.cx * width, y: height * 0.94 - region.cy * height, at: at + k * 0.15 }));
    } else if (profile.burstAt === "behind") {
      points.push({ x: centerX + (random() - 0.5) * bounds.width * 0.15, y: centerY - radius * 0.15, at });
    } else if (profile.burstAt === "above") {
      points.push({ x: centerX + (random() - 0.5) * bounds.width * 0.3, y: Math.max(minY, bounds.y - radius * 0.45), at });
    } else if (profile.burstAt === "sides") {
      const dx = Math.min(maxX, bounds.width / 2 + radius * 0.35);
      points.push({ x: centerX - dx, y: Math.max(minY, centerY - radius * 0.3), at });
      points.push({ x: centerX + dx, y: Math.max(minY, centerY - radius * 0.3), at: at + 0.15 });
    } else {
      const settled = timing.enterAt + 0.6;
      const p = locate(width * (0.2 + random() * 0.6), height * (0.12 + random() * 0.22), settled);
      points.push({ x: p.x, y: p.y, at });
    }
    points.forEach((point, k) => {
      const x = Math.max(-region.cx * width + width * 0.06, Math.min(width * (1 - region.cx) - width * 0.06, point.x));
      const event = { x, y: point.y, at: point.at, spec: main, seed: `${key}${k}`, scale: 1, ...shape(main) };
      bursts.push(event);
      mains.push(event);
      if (withLaunch && main.kind !== "mine") launchTo(x, point.y, point.at, `main${k}`);
    });
  }
  if (text) {
    const glyphs = text.anchors(timing.enterAt).map((anchor, k) => ({ anchor, k })).filter(({ anchor }) => !anchor.blank);
    const sung = profile.sungBurst;
    if (sung) {
      const candidates = glyphs.filter(({ anchor }) => anchor.sungAt >= timing.enterAt && anchor.sungAt < timing.exitAt);
      thin(candidates, MAX_SUNG_BURSTS).forEach(({ anchor, k }, n) => {
        const now = text.anchors(anchor.sungAt)[k] ?? anchor;
        const p = toShot(text.view, now.x, now.y);
        const colors = sung.colors.length > 0 ? sung.colors.map((_, j) => sung.colors[(j + n) % sung.colors.length]) : [n];
        bursts.push({
          x: p.x,
          y: p.y - now.size * 0.1,
          at: anchor.sungAt,
          spec: { ...sung, colors },
          seed: `${input.seed}:${shot.id}:sung${k}`,
          scale: Math.max(0.6, Math.min(1.6, now.size / (unit * 0.1)))
        });
      });
    }
    if (profile.text.exit === "dissolve") {
      const chosen = thin(glyphs, MAX_DISSOLVE_BURSTS);
      const step = Math.min(0.05, timing.exitDuration * 0.6 / Math.max(chosen.length, 1));
      chosen.forEach(({ k }, n) => {
        const at = timing.exitAt + n * step;
        const now = text.anchors(at)[k];
        if (!now) return;
        const p = toShot(text.view, now.x, now.y);
        bursts.push({ x: p.x, y: p.y, at, spec: DISSOLVE_SPARK, seed: `${input.seed}:${shot.id}:dissolve${k}`, scale: 1 });
      });
    }
  }
  bursts.sort((a, b) => a.at - b.at);
  return { bursts, launches, mains };
};

// folia:src/components/visualizer/hanabi/hanabiSceneEntry.ts
var hanabiSpinDirection = (programSeed) => hashVisualizerSeed(`${programSeed}:spin-direction`) % 2 === 0 ? 1 : -1;
var BLUR_EPSILON2 = 0.3;
var buildHanabiSceneEntry = (pixi, context, index) => {
  const { width, height, program } = context;
  const top = Math.max(0, Math.min(height, context.lyricInsets?.top ?? 0));
  const safeHeight = Math.max(1, height - top - Math.max(0, context.lyricInsets?.bottom ?? 0));
  const lyricProfile = (profile) => ({
    ...profile,
    region: { ...profile.region, cy: (top + profile.region.cy * safeHeight) / height, h: profile.region.h * safeHeight / height }
  });
  const paragraph = program.paragraphs[index];
  const lineMap = new Map(paragraph.lineIndices.map((lineIndex, k) => [lineIndex, paragraph.lines[k]]));
  const shots = paragraph.shots.map((shot) => ({
    id: shot.id,
    profile: lyricProfile(resolveShotProfile(shot)),
    startTime: shot.startTime,
    endTime: shot.endTime,
    isBridge: shot.isBridge,
    line: shot.isBridge ? null : shotLine(lineMap, shot.slices)
  }));
  if (shots.length === 0) {
    shots.push({
      id: paragraph.id,
      profile: lyricProfile(resolveShotProfile({ kind: "" })),
      startTime: paragraph.startTime,
      endTime: paragraph.endTime,
      isBridge: true,
      line: null
    });
  }
  const scene = createHanabiScene(pixi, {
    width,
    height,
    tfnInsets: context.lyricInsets,
    resolution: context.resolution,
    seed: `${program.seed}:${paragraph.id}`,
    theme: context.theme,
    tuning: context.tuning,
    shots,
    startTime: paragraph.startTime,
    endTime: paragraph.endTime,
    textures: context.textures,
    exitStart: paragraph.transitionOut?.startTime ?? null,
    motifs: context.motifs,
    icons: context.icons,
    spinDirection: hanabiSpinDirection(program.seed),
    opening: index === 0 && context.songTitle ? { title: context.songTitle, artist: context.songArtist } : null
  });
  scene.setLayerVisibility({ graphics: true, text: context.showText, mid: false });
  const holder = new pixi.Container();
  holder.addChild(scene.view);
  holder.pivot.set(width / 2, height / 2);
  holder.position.set(width / 2, height / 2);
  holder.zIndex = index;
  return { index, scene, holder, blur: null };
};
var applyHanabiLayerFrame = (pixi, entry, frame2, size, blurResolution) => {
  entry.holder.alpha = frame2.alpha;
  entry.holder.scale.set(frame2.scale);
  entry.holder.position.set(size.width / 2, size.height / 2 + frame2.y * size.height);
  entry.holder.rotation = frame2.rotation;
  if (frame2.blur > BLUR_EPSILON2) {
    if (!entry.blur) {
      entry.blur = new pixi.BlurFilter({ strength: frame2.blur, quality: 3, resolution: blurResolution });
    }
    entry.blur.strength = frame2.blur;
    if (!entry.holder.filters?.includes(entry.blur)) {
      entry.holder.filterArea ??= new pixi.Rectangle(-size.width, -size.height, size.width * 3, size.height * 3);
      entry.holder.filters = [entry.blur];
    }
  } else if (entry.holder.filters?.length) {
    entry.holder.filters = [];
  }
};
var destroyHanabiSceneEntry = (entry) => {
  entry.holder.parent?.removeChild(entry.holder);
  entry.holder.filters = [];
  entry.blur?.destroy();
  entry.blur = null;
  entry.holder.removeChild(entry.scene.view);
  entry.scene.destroy();
  entry.holder.destroy();
};

// folia:src/components/visualizer/hanabi/hanabiSceneFrames.ts
var IDLE = { alpha: 1, scale: 1, blur: 0, y: 0, rotation: 0 };
var smooth11 = (value) => {
  const t = Math.min(1, Math.max(0, value));
  return t * t * (3 - 2 * t);
};
var exitFrameOf2 = (program, index, time, beyondBoundary = false) => {
  const out = program.paragraphs[index]?.transitionOut;
  if (!out || time < out.startTime) return IDLE;
  const progress = (time - out.startTime) / Math.max(out.endTime - out.startTime, 1e-3);
  return HANABI_TRANSITIONS[out.kind].resolveFrame("exit", beyondBoundary ? progress : Math.min(progress, 1));
};
var resolveHanabiSceneFrames = (program, time, transitionsEnabled) => {
  if (program.paragraphs.length === 0) return { activeIndex: -1, layers: [] };
  const activeIndex = findHanabiParagraphIndexAtTime(program, time);
  if (!transitionsEnabled) return { activeIndex, layers: [{ index: activeIndex, ...IDLE }] };
  const paragraph = program.paragraphs[activeIndex];
  const current = exitFrameOf2(program, activeIndex, time);
  const layers = [];
  const previousOut = activeIndex > 0 ? program.paragraphs[activeIndex - 1].transitionOut : null;
  if (previousOut) {
    const enterDuration = resolveHanabiEnterDuration(previousOut.kind, previousOut.startTime, previousOut.endTime);
    const progress = (time - paragraph.startTime) / enterDuration;
    if (progress >= 0 && progress < 1) {
      const enter = HANABI_TRANSITIONS[previousOut.kind].resolveFrame("enter", progress);
      const weight = smooth11(progress);
      const leaving = exitFrameOf2(program, activeIndex - 1, time, true);
      if (leaving.alpha * (1 - weight) > 2e-3) {
        layers.push({ index: activeIndex - 1, ...leaving, alpha: leaving.alpha * (1 - weight) });
      }
      layers.push({
        index: activeIndex,
        alpha: Math.min(enter.alpha, weight) * current.alpha,
        scale: enter.scale * current.scale,
        blur: Math.max(enter.blur, current.blur),
        y: enter.y + current.y,
        rotation: enter.rotation + current.rotation
      });
      return { activeIndex, layers };
    }
  }
  layers.push({ index: activeIndex, ...current });
  return { activeIndex, layers };
};

// folia:src/components/visualizer/hanabi/hanabiSky.ts
var hslOfHex = (hex) => {
  const r = (hex >> 16 & 255) / 255;
  const g = (hex >> 8 & 255) / 255;
  const b = (hex & 255) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  const h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h / 6, s, l];
};
var cssOfHsl = ([h, s, l]) => `hsl(${(h % 1 + 1) % 1 * 360}deg ${s * 100}% ${l * 100}%)`;
var leanHue = (from, to, amount) => {
  let delta = to - from;
  if (delta > 0.5) delta -= 1;
  if (delta < -0.5) delta += 1;
  return from + delta * amount;
};
var resolveHanabiSkyStops = (theme) => {
  const [hue, saturation] = hslOfHex(hexOfCss(theme.accentColor, 16743050));
  const lean = (base) => saturation < 0.2 ? base : leanHue(base, hue, 0.3);
  return [
    { at: 0, color: cssOfHsl([lean(0.66), 0.62, 0.06]) },
    { at: 0.45, color: cssOfHsl([lean(0.7), 0.5, 0.11]) },
    { at: 0.82, color: cssOfHsl([lean(0.8), 0.48, 0.19]) },
    { at: 1, color: cssOfHsl([lean(0.9), 0.55, 0.27]) }
  ];
};
var paintSky = (theme) => {
  const canvas = document.createElement("canvas");
  canvas.width = 4;
  canvas.height = 512;
  const context = canvas.getContext("2d");
  const gradient = context.createLinearGradient(0, 0, 0, canvas.height);
  resolveHanabiSkyStops(theme).forEach((stop) => gradient.addColorStop(stop.at, stop.color));
  context.fillStyle = gradient;
  context.fillRect(0, 0, canvas.width, canvas.height);
  return canvas;
};
var HanabiSkyLayer = class {
  constructor(pixi) {
    this.pixi = pixi;
    this.view = new pixi.Container();
    this.sprite = new pixi.Sprite();
    this.view.addChild(this.sprite);
  }
  view;
  sprite;
  texture = null;
  theme = null;
  /** 每帧调用：主题变了才重画渐变，尺寸与不透明度直接改。 */
  update(theme, alpha, width, height) {
    this.view.visible = alpha > 2e-3;
    if (!this.view.visible) return;
    if (theme !== this.theme) {
      this.theme = theme;
      const previous = this.texture;
      this.texture = this.pixi.Texture.from(paintSky(theme));
      this.sprite.texture = this.texture;
      previous?.destroy(true);
    }
    this.sprite.width = width;
    this.sprite.height = height;
    this.view.alpha = alpha;
  }
  destroy() {
    this.texture?.destroy(true);
    this.texture = null;
    this.view.destroy({ children: true });
  }
};

// folia:src/components/visualizer/hanabi/mg/textures.ts
var canvasOf2 = (width, height) => {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  return { canvas, context: canvas.getContext("2d") };
};
var WHITE3 = (alpha) => `rgba(255,255,255,${alpha})`;
var drawDot2 = (size) => {
  const { canvas, context } = canvasOf2(size, size);
  const r = size / 2;
  const gradient = context.createRadialGradient(r, r, 0, r, r, r);
  gradient.addColorStop(0, WHITE3(1));
  gradient.addColorStop(Math.max(0, 1 - 2 / r), WHITE3(1));
  gradient.addColorStop(1, WHITE3(0));
  context.fillStyle = gradient;
  context.fillRect(0, 0, size, size);
  return canvas;
};
var drawGlow = (size) => {
  const { canvas, context } = canvasOf2(size, size);
  const r = size / 2;
  const gradient = context.createRadialGradient(r, r, 0, r, r, r);
  gradient.addColorStop(0, WHITE3(1));
  gradient.addColorStop(0.1, WHITE3(0.95));
  gradient.addColorStop(0.22, WHITE3(0.55));
  gradient.addColorStop(0.42, WHITE3(0.18));
  gradient.addColorStop(0.7, WHITE3(0.05));
  gradient.addColorStop(1, WHITE3(0));
  context.fillStyle = gradient;
  context.fillRect(0, 0, size, size);
  return canvas;
};
var drawStar4 = (size) => {
  const { canvas, context } = canvasOf2(size, size);
  const c = size / 2;
  const r = size * 0.48;
  const halo = context.createRadialGradient(c, c, 0, c, c, r * 0.5);
  halo.addColorStop(0, WHITE3(0.9));
  halo.addColorStop(1, WHITE3(0));
  context.fillStyle = halo;
  context.fillRect(0, 0, size, size);
  const pinch = r * 0.1;
  context.fillStyle = WHITE3(1);
  context.beginPath();
  context.moveTo(c, c - r);
  context.quadraticCurveTo(c + pinch, c - pinch, c + r, c);
  context.quadraticCurveTo(c + pinch, c + pinch, c, c + r);
  context.quadraticCurveTo(c - pinch, c + pinch, c - r, c);
  context.quadraticCurveTo(c - pinch, c - pinch, c, c - r);
  context.closePath();
  context.fill();
  return canvas;
};
var drawStreak2 = (width, height) => {
  const { canvas, context } = canvasOf2(width, height);
  const vertical = context.createLinearGradient(0, 0, 0, height);
  vertical.addColorStop(0, WHITE3(1));
  vertical.addColorStop(0.6, WHITE3(0.6));
  vertical.addColorStop(1, WHITE3(0.28));
  context.fillStyle = vertical;
  context.fillRect(0, 0, width, height);
  context.globalCompositeOperation = "destination-in";
  const horizontal = context.createLinearGradient(0, 0, width, 0);
  horizontal.addColorStop(0, WHITE3(0));
  horizontal.addColorStop(0.3, WHITE3(0.85));
  horizontal.addColorStop(0.5, WHITE3(1));
  horizontal.addColorStop(0.7, WHITE3(0.85));
  horizontal.addColorStop(1, WHITE3(0));
  context.fillStyle = horizontal;
  context.fillRect(0, 0, width, height);
  return canvas;
};
var drawRing = (size) => {
  const { canvas, context } = canvasOf2(size, size);
  const c = size / 2;
  const line2 = Math.max(1.5, size * 0.05);
  context.strokeStyle = WHITE3(1);
  context.lineWidth = line2;
  context.beginPath();
  context.arc(c, c, c - line2, 0, Math.PI * 2);
  context.stroke();
  return canvas;
};
var drawSquare = (size) => {
  const { canvas, context } = canvasOf2(size, size);
  context.fillStyle = WHITE3(1);
  context.fillRect(0, 0, size, size);
  return canvas;
};
var drawTriangle = (size) => {
  const { canvas, context } = canvasOf2(size, size);
  const c = size / 2;
  const r = size * 0.48;
  context.fillStyle = WHITE3(1);
  context.beginPath();
  for (let i = 0; i < 3; i += 1) {
    const a = -Math.PI / 2 + i * Math.PI * 2 / 3;
    const x = c + Math.cos(a) * r;
    const y = c + Math.sin(a) * r * 1 + r * 0.12;
    if (i === 0) context.moveTo(x, y);
    else context.lineTo(x, y);
  }
  context.closePath();
  context.fill();
  return canvas;
};
var drawPetal = (width, height) => {
  const { canvas, context } = canvasOf2(width, height);
  const cx = width / 2;
  const top = height * 0.06;
  const bottom = height * 0.96;
  const notch = height * 0.16;
  context.fillStyle = WHITE3(1);
  context.beginPath();
  context.moveTo(cx, bottom);
  context.bezierCurveTo(cx - width * 0.62, height * 0.62, cx - width * 0.5, top, cx - width * 0.14, top);
  context.lineTo(cx, top + notch);
  context.lineTo(cx + width * 0.14, top);
  context.bezierCurveTo(cx + width * 0.5, top, cx + width * 0.62, height * 0.62, cx, bottom);
  context.closePath();
  context.fill();
  return canvas;
};
var createHanabiTextures = (pixi, resolution) => {
  const scale = Math.max(0.5, Math.min(4, resolution || 1));
  const px = (base) => Math.max(4, Math.min(1024, Math.round(base * scale)));
  const make = (canvas) => pixi.Texture.from(canvas);
  const textures = {
    dot: make(drawDot2(px(32))),
    glow: make(drawGlow(px(96))),
    star4: make(drawStar4(px(96))),
    streak: make(drawStreak2(px(16), px(128))),
    ring: make(drawRing(px(160))),
    square: make(drawSquare(px(8))),
    triangle: make(drawTriangle(px(48))),
    petal: make(drawPetal(px(32), px(44)))
  };
  return {
    ...textures,
    destroy: () => Object.values(textures).forEach((texture) => texture.destroy(true))
  };
};

// folia:src/components/visualizer/hanabi/overlay.ts
var buildHanabiOverlay = (pixi, width, height, theme, colorMode, resolution = 1) => {
  const container = new pixi.Container();
  const palette = resolveHanabiPalette("kawaii", theme, colorMode);
  const unit = Math.min(width, height);
  const padX = Math.max(width * 0.07, unit * 0.06);
  const padY = Math.max(height * 0.08, unit * 0.06);
  const line2 = Math.max(1.2, unit / 640);
  const font = resolveThemeFontStack(theme);
  const weight = String(resolveThemeFontWeight(theme, 700));
  const g = new pixi.Graphics();
  const seal = unit * 0.024;
  const sealX = padX + seal;
  const sealY = padY + seal;
  g.circle(sealX, sealY, seal).fill({ color: palette.blocks[0], alpha: 0.85 });
  g.circle(sealX, sealY, seal * 1.28).stroke({ color: palette.blocks[0], width: line2, alpha: 0.5 });
  const sealText = new pixi.Text({
    text: "\u82B1\u706B",
    style: new pixi.TextStyle({ fontFamily: font, fontWeight: weight, fontSize: seal * 0.66, fill: palette.ink, letterSpacing: -seal * 0.04 }),
    resolution
  });
  sealText.anchor.set(0.5);
  sealText.position.set(sealX, sealY);
  const letterSize = unit * 0.017;
  const letters = Array.from("HANABI").map((char, i) => {
    const label = new pixi.Text({
      text: char,
      style: new pixi.TextStyle({ fontFamily: font, fontWeight: weight, fontSize: letterSize, fill: palette.paper }),
      resolution
    });
    label.anchor.set(0.5);
    label.alpha = 0.55;
    label.position.set(width - padX, padY + letterSize * (0.6 + i * 1.5));
    return label;
  });
  const stemTop = padY + letterSize * (0.6 + 6 * 1.5);
  g.moveTo(width - padX, stemTop).lineTo(width - padX, stemTop + unit * 0.08).stroke({ color: palette.paper, width: line2, alpha: 0.35 });
  const dotY = height - padY;
  palette.sparks.slice(0, 3).forEach((color, i) => {
    g.circle(padX + i * unit * 0.018, dotY, unit * 55e-4).fill({ color, alpha: 0.85 });
  });
  g.moveTo(padX + unit * 0.05, dotY).lineTo(padX + unit * 0.16, dotY).stroke({ color: palette.paper, width: line2, alpha: 0.35 });
  const arm = unit * 0.035;
  g.moveTo(width - padX - arm, height - padY).lineTo(width - padX, height - padY).lineTo(width - padX, height - padY - arm).stroke({ color: palette.accent, width: line2 * 1.4, alpha: 0.6 });
  container.addChild(g, sealText, ...letters);
  return container;
};

// folia:src/components/visualizer/hanabi/createHanabiPixiRuntime.ts
var REBUILD_DEBOUNCE_MS2 = 220;
var MIN_WIDTH2 = 320;
var MIN_HEIGHT2 = 240;
var DARK_SKY = 0.5;
var NIGHT_BACKGROUND = "#0b0d24";
var resolveRenderResolution = (devicePixelRatio, scale) => resolveLyricPixelRatio(resolveHanabiBaseResolution(devicePixelRatio), scale);
var HanabiPixiRuntime = class _HanabiPixiRuntime extends TfnPixiSceneHandoff {
  constructor(pixi, options, app) {
    super();
    this.pixi = pixi;
    this.options = options;
    this.app = app;
  }
  tfnViewport = new TfnLyricViewport();
  tfnActive = true;
  tfnTop = 0;
  tfnBottom = 0;
  setTfnFrameRate(value) {
    this.app.ticker.maxFPS = Math.max(15, Math.min(60, value));
  }
  setTfnLyricScale(scale) {
    if (window.tfnLyricScale === scale) return;
    window.tfnLyricScale = scale;
    this.rebuildDue = true;
    this.renderOnce();
  }
  get tfnHeight() {
    return Math.max(120, this.height - this.tfnTop - this.tfnBottom);
  }
  setTfnInsets(top, bottom, animate = true) {
    this.tfnViewport.set(top, bottom, animate);
    this.tfnTop = top;
    this.tfnBottom = bottom;
    this.renderOnce();
    if (this.tfnViewport.moving && this.tfnActive && !this.options.staticMode) this.app.start();
  }
  setTfnActive(active) {
    this.tfnActive = active;
    if (!active) {
      this.tfnViewport.finish();
      this.tfnFinishSceneHandoff();
      this.app.stop();
    }
  }
  sceneCache = new PixiSceneCache({
    count: () => this.options.song.program.paragraphs.length,
    build: (index) => {
      const entry = this.buildEntry(this.options.song, index);
      this.sceneLayer.addChild(entry.holder);
      return entry;
    },
    destroy: (entry) => destroyHanabiSceneEntry(entry),
    detach: (entry) => entry.holder.parent?.removeChild(entry.holder)
  });
  songSwap = new PixiSongSwap({
    stage: (song) => this.stageSong(song),
    commit: (song, staged) => this.commitSong(song, staged),
    discard: (entry) => destroyHanabiSceneEntry(entry)
  });
  activeIndex = -1;
  destroyed = false;
  resizeObserver = null;
  width = 0;
  height = 0;
  renderResolution = 1;
  rebuildTimer = null;
  rebuildDue = false;
  /** 场景、片尾卡、画框用的主题：夜空够深时背景色换成夜色，配色按深色底取。 */
  sceneTheme = null;
  textures = null;
  texturesResolution = 0;
  /** 分辨率变了换下来的纹理：还被已建好的场景用着，等场景都换掉后再放。 */
  retiredTextures = [];
  /** 上一次重建之后，换下来的纹理可以放了。 */
  texturesReleasable = false;
  /** 全屏辉光：第一次需要时才建；滤镜区域固定为整个画面（随内容包围盒变会让降采样网格跟着抖）。 */
  screenBloom = null;
  screenBloomArea = null;
  /** 每帧交给场景的「随拍开花」输入（就地改，不分配）。 */
  beatSource = { events: [], strength: 0, trackScale: 1 };
  sky;
  sceneLayer;
  overlayLayer;
  credits;
  static async create(options) {
    const pixi = await loadPixi();
    const contextOptions = {
      // 画布透明：夜空不透明度小于 1 时 folia 的共享背景要透出来。
      backgroundAlpha: 0,
      antialias: options.antialias,
      powerPreference: "high-performance"
    };
    const context = await makePixiContext(pixi, contextOptions, options.signal);
    const app = new pixi.Application();
    const width = Math.max(options.host.clientWidth, MIN_WIDTH2);
    const height = Math.max(options.host.clientHeight, MIN_HEIGHT2);
    const resolution = resolveRenderResolution(Math.min(window.devicePixelRatio || 1, window.tfnPerformance?.pixelRatioCap ?? 1.5), options.renderScale);
    await app.init({
      width,
      height,
      ...contextOptions,
      ...context,
      autoDensity: true,
      resolution,
      autoStart: false,
      sharedTicker: false,
      preference: "webgl"
    });
    if (app.renderer.type !== pixi.RendererType.WEBGL) {
      app.destroy({ removeView: true });
      throw new Error("Hanabi requires WebGL");
    }
    const gl = app.renderer.gl;
    if (gl) setHanabiGlyphTextureLimit(gl.getParameter(gl.MAX_TEXTURE_SIZE));
    const runtime = new _HanabiPixiRuntime(pixi, options, app);
    runtime.renderResolution = resolution;
    runtime.sky = new HanabiSkyLayer(pixi);
    runtime.sceneLayer = new pixi.Container();
    runtime.sceneLayer.sortableChildren = true;
    runtime.overlayLayer = new pixi.Container();
    runtime.credits = new HanabiCreditsLayer(pixi);
    app.stage.addChild(runtime.sky.view, runtime.sceneLayer, runtime.credits.holder, runtime.overlayLayer);
    if (options.signal?.aborted) {
      runtime.destroy();
      throw new DOMException("Hanabi runtime creation was cancelled", "AbortError");
    }
    await runtime.install();
    if (options.signal?.aborted) {
      runtime.destroy();
      throw new DOMException("Hanabi runtime creation was cancelled", "AbortError");
    }
    return runtime;
  }
  /** 第一帧分几步做（同绘光）：建上下文后另起一个任务建第一个场景并链接着色器，之后画布才放上页面。 */
  async install() {
    await new Promise((resolve) => {
      window.setTimeout(resolve);
    });
    if (this.options.signal?.aborted) return;
    this.resizeToHost(true);
    this.renderFrame();
    await linkPixiPrograms(this.pixi, this.app.renderer, this.app.stage, "Hanabi", this.options.signal);
    if (this.options.signal?.aborted) return;
    this.options.host.appendChild(this.app.canvas);
    this.app.canvas.style.cssText = "width:100%;height:100%;display:block";
    this.app.ticker.maxFPS = window.tfnPerformance?.maxFps ?? 30;
    this.app.ticker.add(this.renderFrame);
    this.resizeObserver = new ResizeObserver(() => {
      if (this.destroyed || !this.resizeToHost(false)) return;
      if (this.options.paused) this.renderOnce();
    });
    this.resizeObserver.observe(this.options.host);
    this.app.renderer.render(this.app.stage);
    if (!this.options.paused) this.app.start();
  }
  /** 尺寸没变返回 false。渲染器立刻跟上，场景（尺寸烘焙在里面）防抖重建。 */
  resizeToHost(immediate) {
    if (this.destroyed) return false;
    const width = Math.max(this.options.host.clientWidth, MIN_WIDTH2);
    const height = Math.max(this.options.host.clientHeight, MIN_HEIGHT2);
    const resolution = resolveRenderResolution(Math.min(window.devicePixelRatio || 1, window.tfnPerformance?.pixelRatioCap ?? 1.5), this.options.renderScale);
    if (width === this.width && height === this.height && resolution === this.renderResolution) return false;
    this.width = width;
    this.height = height;
    this.renderResolution = resolution;
    this.app.renderer.resize(width, height, resolution);
    this.drawOverlay();
    if (immediate) this.rebuildDue = true;
    else this.scheduleRebuild();
    return true;
  }
  scheduleRebuild() {
    if (this.rebuildTimer !== null) clearTimeout(this.rebuildTimer);
    this.rebuildTimer = setTimeout(() => {
      this.rebuildTimer = null;
      if (this.destroyed) return;
      this.rebuildDue = true;
      if (this.options.paused) this.renderOnce();
    }, REBUILD_DEBOUNCE_MS2);
  }
  themeFor(theme) {
    const dark = !this.options.tuning.textOnly && this.options.tuning.sky >= DARK_SKY;
    if (this.sceneTheme?.source !== theme || this.sceneTheme.dark !== dark) {
      this.sceneTheme = { source: theme, dark, theme: dark ? { ...theme, backgroundColor: NIGHT_BACKGROUND } : theme };
    }
    return this.sceneTheme.theme;
  }
  texturesNow() {
    if (!this.textures || this.texturesResolution !== this.renderResolution) {
      if (this.textures) this.retiredTextures.push(this.textures);
      this.textures = createHanabiTextures(this.pixi, this.renderResolution);
      this.texturesResolution = this.renderResolution;
    }
    return this.textures;
  }
  drawOverlay() {
    destroyPixiContainerChildren(this.overlayLayer);
    const { tuning } = this.options;
    if (!tuning.overlayFrame || tuning.textOnly || this.width === 0) return;
    this.overlayLayer.addChild(buildHanabiOverlay(
      this.pixi,
      this.width,
      this.height,
      this.themeFor(this.options.song.theme),
      tuning.colorMode,
      this.renderResolution
    ));
  }
  buildEntry(song, index) {
    return buildHanabiSceneEntry(this.pixi, {
      width: this.width,
      height: this.height,
      lyricInsets: { top: this.tfnTop, bottom: this.tfnBottom },
      resolution: this.renderResolution,
      program: song.program,
      theme: this.themeFor(song.theme),
      tuning: this.options.tuning,
      textures: this.texturesNow(),
      showText: this.options.showText,
      motifs: this.motifs(),
      songTitle: this.options.metadata.title?.trim() || null,
      songArtist: this.options.metadata.artist?.trim() || null,
      icons: this.iconsFor(song.theme)
    }, index);
  }
  /** 拼贴的字样：曲名在前，再是 HANABI / 花火（没有关键词时重复字用它们）。 */
  motifs() {
    const title = this.options.metadata.title?.trim();
    return [...title ? [title] : [], "HANABI", "\u82B1\u706B"];
  }
  /** 主题图标里已经加载好的那些（外壳在建运行时与换歌前加载）；一个都没有时拼贴用花。 */
  iconsFor(theme) {
    return resolveLucideIconNames(theme.lyricsIcons);
  }
  clearScenes() {
    this.sceneCache.clear();
    this.activeIndex = -1;
  }
  /**
   * 换下来的纹理只在分辨率变化时出现，而分辨率变化总会跟着一次重建：重建清掉缓存场景与片尾卡之后（换歌换下、
   * 还没销毁完的场景也放完），就没有谁再用它们了。重建之前（防抖期间）旧场景还在画，不能放。
   */
  releaseRetiredTextures() {
    if (!this.texturesReleasable || this.sceneCache.hasRetired || this.songSwap.active) return;
    this.texturesReleasable = false;
    this.retiredTextures.splice(0).forEach((textures) => textures.destroy());
  }
  renderFrame = () => {
    if (this.destroyed) return;
    if (this.options.staticMode || !this.tfnActive) this.tfnViewport.finish();
    const viewport = this.tfnViewport.sample();
    this.songSwap.advance();
    const time = this.options.currentTime.get();
    if (this.rebuildDue) {
      this.rebuildDue = false;
      this.songSwap.dropStaged();
      this.clearScenes();
      this.credits.invalidate();
      this.texturesNow();
      if (this.retiredTextures.length > 0) this.texturesReleasable = true;
    }
    const { program, theme } = this.options.song;
    const { tuning } = this.options;
    this.sky.update(theme, tuning.textOnly ? 0 : tuning.sky, this.width, this.height);
    const frames = resolveHanabiSceneFrames(program, time, !this.options.staticMode);
    let builtThisFrame = false;
    if (frames.activeIndex !== this.activeIndex) {
      this.activeIndex = frames.activeIndex;
      this.sceneCache.prune(frames.activeIndex, new Set(frames.layers.map((layer) => layer.index)));
    }
    frames.layers.forEach((layer) => {
      if (!this.sceneCache.has(layer.index)) {
        this.sceneCache.ensure(layer.index);
        builtThisFrame = true;
      }
    });
    const creditsFrame = this.credits.resolveFrame(time, program, this.options.metadata);
    if (!builtThisFrame && !this.songSwap.active && !this.tfnSceneHandoff) {
      const next = frames.activeIndex + 1;
      const previous = frames.activeIndex - 1;
      if (this.sceneCache.hasRetired) {
        this.sceneCache.drainRetired();
      } else if (this.prepareShots(time)) {
      } else if (next < program.paragraphs.length && !this.sceneCache.has(next)) {
        this.sceneCache.ensure(next);
      } else if (this.credits.needsBuild(time, program, this.options.metadata)) {
        this.credits.build(this.creditBuildContext(theme));
      } else if (previous >= 0 && !this.sceneCache.has(previous)) {
        this.sceneCache.ensure(previous);
      }
    }
    if (creditsFrame.active && !this.credits.built && this.credits.hasMetadata(this.options.metadata)) {
      this.credits.build(this.creditBuildContext(theme));
    }
    this.releaseRetiredTextures();
    const beats = this.readBeatSource();
    this.applyBeatPulse();
    this.applyScreenBloom(time);
    const lyricAlpha = creditsFrame.active ? creditsFrame.lyricAlpha : 1;
    const lyricBlur = creditsFrame.active ? creditsFrame.lyricBlur : 0;
    const blurResolution = this.renderResolution * 0.5;
    const sceneMix = this.tfnSceneMix();
    const spinTurn = tuning.textOnly ? 0 : tuning.spin * hanabiSpinDirection(program.seed);
    this.sceneCache.forEach((entry, index) => {
      const layer = frames.layers.find((candidate) => candidate.index === index);
      const alpha = (layer?.alpha ?? 0) * lyricAlpha * sceneMix;
      entry.holder.visible = alpha > 2e-3;
      if (!entry.holder.visible || !layer) return;
      if (viewport) entry.scene.setTfnViewport(viewport);
      entry.scene.update(time, beats);
      applyHanabiLayerFrame(this.pixi, entry, {
        alpha,
        scale: layer.scale,
        blur: Math.max(layer.blur, lyricBlur),
        y: layer.y,
        // 段落转场的旋转跟着「旋转」设置与整首歌的旋转方向走；仅显示歌词文字时不转。
        rotation: layer.rotation * spinTurn
      }, { width: this.width, height: this.height }, blurResolution);
    });
    this.tfnRenderOutgoing(sceneMix);
    this.tfnLastSceneTime = time;
    this.tfnLastSceneTop = this.sceneLayer.y;
    if (this.options.paused && !this.tfnViewport.moving) this.app.stop();
    this.credits.update(time, creditsFrame, this.width, this.tfnHeight);
    if (this.credits.holder.visible) this.credits.holder.y += this.tfnTop;
  };
  /** 缓存里的场景（当前段与预建好的下一段）谁有马上要出场的镜头就备一个；做了返回 true。 */
  prepareShots(time) {
    let done = false;
    this.sceneCache.forEach((entry) => {
      if (!done) done = entry.scene.prepare(time);
    });
    return done;
  }
  /** 「随拍开花」这一帧的输入；节拍表没装好、效果关着、静态模式时为 null。 */
  readBeatSource() {
    if (this.options.staticMode || this.options.tuning.textOnly || !isBeatFxReady()) return null;
    const strength = getBeatEffectStrength(BEAT_EFFECT_IDS.hanabiBeatBursts);
    if (strength <= 0) return null;
    this.beatSource.events = getBeatFxEvents();
    this.beatSource.strength = strength;
    this.beatSource.trackScale = getBeatFxTrackScale();
    return this.beatSource;
  }
  /** 全屏辉光：强度为 0 时摘掉 filter，否则挂上并按画面尺寸固定滤镜区域。 */
  applyScreenBloom(time) {
    const { tuning, song } = this.options;
    const strength = resolveHanabiScreenBloomStrength(tuning.bloom, tuning.chorusBloom, resolveHanabiChorusWeight(song.program.chorus, time));
    if (strength <= 0.01) {
      if (this.sceneLayer.filters?.length) this.sceneLayer.filters = [];
      return;
    }
    if (!this.screenBloom) {
      this.screenBloom = createBloomFilter(this.pixi, { strength, threshold: 0.5, knee: 0.3, levels: 5, spread: 0.85, tint: [1, 0.95, 0.98], padding: 0 });
      this.screenBloom.resolution = "inherit";
      this.screenBloomArea = new this.pixi.Rectangle();
    }
    this.screenBloom.options.strength = strength;
    this.screenBloomArea.x = 0;
    this.screenBloomArea.y = 0;
    this.screenBloomArea.width = this.width;
    this.screenBloomArea.height = this.height;
    this.sceneLayer.filterArea = this.screenBloomArea;
    if (!this.sceneLayer.filters?.includes(this.screenBloom)) this.sceneLayer.filters = [this.screenBloom];
  }
  /** 「随拍推镜」：整个场景层以画面中心推近、左右轻摆；没有拍时复原。 */
  applyBeatPulse() {
    const strength = this.options.staticMode || this.options.tuning.textOnly || !isBeatFxReady() ? 0 : getBeatEffectStrength(BEAT_EFFECT_IDS.hanabiBeatPulse);
    this.sceneLayer.pivot.set(this.width / 2, this.height / 2);
    this.sceneLayer.position.set(this.width / 2, this.height / 2);
    if (strength <= 0) {
      this.sceneLayer.scale.set(1);
      this.sceneLayer.rotation = 0;
      return;
    }
    const clock = getBeatFxIntensities();
    const pulse = resolveHanabiBeatPulse(
      rescaleBeatEnvelope(beatImpact.get(), clock.beat, strength),
      rescaleBeatEnvelope(downbeatImpact.get(), clock.downbeat, strength),
      getBeatFxRotationSign()
    );
    this.sceneLayer.scale.set(pulse.scale);
    this.sceneLayer.rotation = pulse.rotation;
  }
  creditBuildContext(theme) {
    return {
      width: this.width,
      height: this.tfnHeight,
      resolution: this.renderResolution,
      theme: this.themeFor(theme),
      metadata: this.options.metadata,
      tuning: this.options.tuning,
      textures: this.texturesNow(),
      icons: this.iconsFor(theme)
    };
  }
  renderOnce() {
    if (this.destroyed || !this.app.canvas.isConnected) return;
    this.renderFrame();
    if (this.destroyed) return;
    this.app.renderer.render(this.app.stage);
  }
  /**
   * 换歌：新歌当前段落的场景在第一帧建好（旧歌还在画），第二帧切过去；换下的场景之后一帧销毁一个。
   * 不是真正的换歌（同一个 seed：主题改了、歌词晚到）、暂停中、还没有画面时直接替换。
   */
  async swapSong(next, signal) {
    if (this.tfnSceneHandoff) await this.tfnSceneHandoff.finished;
    if (this.destroyed) return;
    if (sameTfnTrack(next, this.options.song) || this.songSwap.active || this.width === 0 || this.sceneCache.size === 0 || this.options.paused || signal?.aborted) {
      this.commitSong(next, null);
      if (this.options.paused) this.renderOnce();
      return Promise.resolve();
    }
    await this.songSwap.begin(next, signal);
    if (this.tfnSceneHandoff) await this.tfnSceneHandoff.finished;
  }
  /** 交接的第一帧：离屏建好新歌当前段落的场景（不进缓存，旧歌的场景被换下时它不受影响）。 */
  stageSong(song) {
    const index = findHanabiParagraphIndexAtTime(song.program, song.currentTime?.get() ?? this.options.currentTime.get());
    if (index < 0 || index >= song.program.paragraphs.length) return null;
    const entry = this.buildEntry(song, index);
    entry.holder.visible = false;
    this.sceneLayer.addChild(entry.holder);
    return entry;
  }
  tfnUpdateOutgoingEntry(entry, time) {
    entry.scene.update(time, null);
  }
  commitSong(next, staged) {
    if (next.mixHandoff && !sameTfnTrack(next, this.options.song)) this.tfnRetainScenes();
    const themeChanged = next.theme !== this.options.song.theme;
    this.options.song = next;
    if (staged) {
      this.sceneCache.retireAll();
      this.sceneCache.adopt(staged.index, staged);
      this.activeIndex = staged.index;
    } else {
      this.clearScenes();
    }
    this.credits.invalidate();
    if (themeChanged) this.drawOverlay();
  }
  /** 就地应用 tuning：夜空每帧现读，画框按需重画，烘焙进场景的字段（含夜空深浅换配色）防抖重建。 */
  setTuning(tuning) {
    if (this.destroyed || tuning === this.options.tuning) return;
    const previous = this.options.tuning;
    this.options.tuning = tuning;
    const darkChanged = previous.sky >= DARK_SKY !== tuning.sky >= DARK_SKY;
    if (changedHanabiKeys(previous, tuning, HANABI_OVERLAY_KEYS) || darkChanged) this.drawOverlay();
    if (requiresHanabiSceneRebuild(previous, tuning) || darkChanged) this.scheduleRebuild();
    if (this.options.paused) this.renderOnce();
  }
  /** 就地换分辨率倍数：同窗口缩放，渲染器立刻跟上，场景（字形图集、粒子纹理按分辨率画）防抖重建。 */
  setRenderScale(scale) {
    if (this.destroyed || scale === this.options.renderScale) return;
    this.options.renderScale = scale;
    if (this.width === 0) return;
    if (this.resizeToHost(false) && this.options.paused) this.renderOnce();
  }
  setShowText(showText) {
    if (this.destroyed || showText === this.options.showText) return;
    this.options.showText = showText;
    const apply = (entry) => entry.scene.setLayerVisibility({ graphics: true, text: showText, mid: false });
    this.sceneCache.forEach(apply);
    if (this.songSwap.staged) apply(this.songSwap.staged);
    if (this.options.paused) this.renderOnce();
  }
  setStaticMode(staticMode) {
    if (this.destroyed || staticMode === this.options.staticMode) return;
    this.options.staticMode = staticMode;
    if (staticMode) this.tfnFinishSceneHandoff();
    if (this.options.paused) this.renderOnce();
  }
  setSongMetadata(metadata) {
    if (this.destroyed) return;
    const current = this.options.metadata;
    if (current.title === metadata.title && current.artist === metadata.artist && current.album === metadata.album) return;
    const titleChanged = current.title?.trim() !== metadata.title?.trim() || current.artist?.trim() !== metadata.artist?.trim();
    this.options.metadata = { ...metadata };
    this.credits.invalidate();
    if (titleChanged) this.scheduleRebuild();
    if (this.options.paused) this.renderOnce();
  }
  setPaused(paused) {
    if (this.destroyed) return;
    this.options.paused = paused;
    if (paused) {
      this.tfnFinishSceneHandoff();
      this.songSwap.settle(true);
      this.app.stop();
      this.renderOnce();
    } else {
      this.app.start();
    }
  }
  destroy() {
    if (this.destroyed) return;
    this.destroyed = true;
    this.songSwap.settle(false);
    this.tfnFinishSceneHandoff();
    if (this.rebuildTimer !== null) clearTimeout(this.rebuildTimer);
    this.rebuildTimer = null;
    this.resizeObserver?.disconnect();
    this.resizeObserver = null;
    this.app.stop();
    this.app.ticker.remove(this.renderFrame);
    this.sceneCache.destroyAll();
    this.credits?.destroy();
    this.sky?.destroy();
    if (this.sceneLayer) this.sceneLayer.filters = [];
    this.screenBloom?.destroy();
    this.screenBloom = null;
    if (this.overlayLayer) destroyPixiContainerChildren(this.overlayLayer);
    this.textures?.destroy();
    this.retiredTextures.splice(0).forEach((textures) => textures.destroy());
    this.app.destroy({ removeView: true }, { children: true });
  }
};
export {
  DEFAULT_HANABI_TUNING,
  DEFAULT_LUMIERE_TUNING,
  HanabiPixiRuntime,
  LumierePixiRuntime,
  compileHanabiProgram,
  compileLumiereProgram
};
