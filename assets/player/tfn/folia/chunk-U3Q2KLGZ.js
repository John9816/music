// Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; adapted for TuneFreeNext. See THIRD_PARTY_NOTICES.md and scripts/vendor_folia_skins.mjs.
import {
  BindGroup
} from "./chunk-2SNS7NNO.js";
import {
  Texture
} from "./chunk-NJ7XHR5M.js";

// scripts/folia/node_modules/pixi.js/lib/rendering/batcher/gpu/getTextureBatchBindGroup.mjs
var cachedGroups = {};
function getTextureBatchBindGroup(textures, size, maxTextures) {
  let uid = 2166136261;
  for (let i = 0; i < size; i++) {
    uid ^= textures[i].uid;
    uid = Math.imul(uid, 16777619);
    uid >>>= 0;
  }
  return cachedGroups[uid] || generateTextureBatchBindGroup(textures, size, uid, maxTextures);
}
function generateTextureBatchBindGroup(textures, size, key, maxTextures) {
  const bindGroupResources = {};
  let bindIndex = 0;
  for (let i = 0; i < maxTextures; i++) {
    const texture = i < size ? textures[i] : Texture.EMPTY.source;
    bindGroupResources[bindIndex++] = texture.source;
    bindGroupResources[bindIndex++] = texture.style;
  }
  const bindGroup = new BindGroup(bindGroupResources);
  cachedGroups[key] = bindGroup;
  return bindGroup;
}

export {
  getTextureBatchBindGroup
};
