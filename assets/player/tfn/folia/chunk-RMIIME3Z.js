// Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; adapted for TuneFreeNext. See THIRD_PARTY_NOTICES.md and scripts/vendor_folia_skins.mjs.
import {
  BigPool,
  Bounds,
  Color,
  DEG_TO_RAD,
  ExtensionType,
  GlobalResourceRegistry,
  InstructionSet,
  Matrix,
  Point,
  RAD_TO_DEG,
  ScreenSizeRegistry,
  Texture,
  TextureSource,
  TextureStyle,
  deprecation,
  eventemitter3_default,
  extensions,
  isPow2,
  multiplyHexColors,
  nextPow2,
  uid,
  v8_0_0,
  v8_21_0,
  warn
} from "./chunk-NJ7XHR5M.js";

// scripts/folia/node_modules/pixi.js/lib/culling/cullingMixin.mjs
var cullingMixin = {
  cullArea: null,
  cullable: false,
  cullableChildren: true
};

// scripts/folia/node_modules/pixi.js/lib/maths/point/ObservablePoint.mjs
var ObservablePoint = class _ObservablePoint {
  /**
   * Creates a new `ObservablePoint`
   * @param observer - Observer to pass to listen for change events.
   * @param {number} [x=0] - position of the point on the x axis
   * @param {number} [y=0] - position of the point on the y axis
   */
  constructor(observer, x, y) {
    this._x = x || 0;
    this._y = y || 0;
    this._observer = observer;
  }
  /**
   * Creates a clone of this point.
   * @example
   * ```ts
   * // Basic cloning
   * const point = new ObservablePoint(observer, 100, 200);
   * const copy = point.clone();
   *
   * // Clone with new observer
   * const newObserver = {
   *     _onUpdate: (p) => console.log(`Clone updated: (${p.x}, ${p.y})`)
   * };
   * const watched = point.clone(newObserver);
   *
   * // Verify independence
   * watched.set(300, 400); // Only triggers new observer
   * ```
   * @param observer - Optional observer to pass to the new observable point
   * @returns A copy of this observable point
   * @see {@link ObservablePoint.copyFrom} For copying into existing point
   * @see {@link Observer} For observer interface details
   */
  clone(observer) {
    return new _ObservablePoint(observer ?? this._observer, this._x, this._y);
  }
  /**
   * Sets the point to a new x and y position.
   *
   * If y is omitted, both x and y will be set to x.
   * @example
   * ```ts
   * // Basic position setting
   * const point = new ObservablePoint(observer);
   * point.set(100, 200);
   *
   * // Set both x and y to same value
   * point.set(50); // x=50, y=50
   * ```
   * @param x - Position on the x axis
   * @param y - Position on the y axis, defaults to x
   * @returns The point instance itself
   * @see {@link ObservablePoint.copyFrom} For copying from another point
   * @see {@link ObservablePoint.equals} For comparing positions
   */
  set(x = 0, y = x) {
    if (this._x !== x || this._y !== y) {
      this._x = x;
      this._y = y;
      this._observer._onUpdate(this);
    }
    return this;
  }
  /**
   * Copies x and y from the given point into this point.
   * @example
   * ```ts
   * // Basic copying
   * const source = new ObservablePoint(observer, 100, 200);
   * const target = new ObservablePoint();
   * target.copyFrom(source);
   *
   * // Copy and chain operations
   * const point = new ObservablePoint()
   *     .copyFrom(source)
   *     .set(x + 50, y + 50);
   *
   * // Copy from any PointData
   * const data = { x: 10, y: 20 };
   * point.copyFrom(data);
   * ```
   * @param p - The point to copy from
   * @returns The point instance itself
   * @see {@link ObservablePoint.copyTo} For copying to another point
   * @see {@link ObservablePoint.clone} For creating new point copy
   */
  copyFrom(p) {
    if (this._x !== p.x || this._y !== p.y) {
      this._x = p.x;
      this._y = p.y;
      this._observer._onUpdate(this);
    }
    return this;
  }
  /**
   * Copies this point's x and y into the given point.
   * @example
   * ```ts
   * // Basic copying
   * const source = new ObservablePoint(100, 200);
   * const target = new ObservablePoint();
   * source.copyTo(target);
   * ```
   * @param p - The point to copy to. Can be any type that is or extends `PointLike`
   * @returns The point (`p`) with values updated
   * @see {@link ObservablePoint.copyFrom} For copying from another point
   * @see {@link ObservablePoint.clone} For creating new point copy
   */
  copyTo(p) {
    p.set(this._x, this._y);
    return p;
  }
  /**
   * Checks if another point is equal to this point.
   *
   * Compares x and y values using strict equality.
   * @example
   * ```ts
   * // Basic equality check
   * const p1 = new ObservablePoint(100, 200);
   * const p2 = new ObservablePoint(100, 200);
   * console.log(p1.equals(p2)); // true
   *
   * // Compare with PointData
   * const data = { x: 100, y: 200 };
   * console.log(p1.equals(data)); // true
   *
   * // Check different points
   * const p3 = new ObservablePoint(200, 300);
   * console.log(p1.equals(p3)); // false
   * ```
   * @param p - The point to check
   * @returns `true` if both `x` and `y` are equal
   * @see {@link ObservablePoint.copyFrom} For making points equal
   * @see {@link PointData} For point data interface
   */
  equals(p) {
    return p.x === this._x && p.y === this._y;
  }
  toString() {
    return `[pixi.js/math:ObservablePoint x=${this._x} y=${this._y} scope=${this._observer}]`;
  }
  /**
   * Position of the observable point on the x axis.
   * Triggers observer callback when value changes.
   * @example
   * ```ts
   * // Basic x position
   * const point = new ObservablePoint(observer);
   * point.x = 100; // Triggers observer
   *
   * // Use in calculations
   * const width = rightPoint.x - leftPoint.x;
   * ```
   * @default 0
   */
  get x() {
    return this._x;
  }
  set x(value) {
    if (this._x !== value) {
      this._x = value;
      this._observer._onUpdate(this);
    }
  }
  /**
   * Position of the observable point on the y axis.
   * Triggers observer callback when value changes.
   * @example
   * ```ts
   * // Basic y position
   * const point = new ObservablePoint(observer);
   * point.y = 200; // Triggers observer
   *
   * // Use in calculations
   * const height = bottomPoint.y - topPoint.y;
   * ```
   * @default 0
   */
  get y() {
    return this._y;
  }
  set y(value) {
    if (this._y !== value) {
      this._y = value;
      this._observer._onUpdate(this);
    }
  }
};

// scripts/folia/node_modules/pixi.js/lib/scene/container/container-mixins/cacheAsTextureMixin.mjs
var cacheAsTextureMixin = {
  get isCachedAsTexture() {
    return !!this.renderGroup?.isCachedAsTexture;
  },
  cacheAsTexture(val) {
    if (typeof val === "boolean" && val === false) {
      this.disableRenderGroup();
    } else {
      this.enableRenderGroup();
      this.renderGroup.enableCacheAsTexture(val === true ? {} : val);
    }
  },
  updateCacheTexture() {
    this.renderGroup?.updateCacheTexture();
  },
  get cacheAsBitmap() {
    return this.isCachedAsTexture;
  },
  set cacheAsBitmap(val) {
    deprecation("v8.6.0", "cacheAsBitmap is deprecated, use cacheAsTexture instead.");
    this.cacheAsTexture(val);
  }
};

// scripts/folia/node_modules/pixi.js/lib/utils/data/removeItems.mjs
function removeItems(arr, startIdx, removeCount) {
  const length = arr.length;
  let i;
  if (startIdx >= length || removeCount === 0) {
    return;
  }
  removeCount = startIdx + removeCount > length ? length - startIdx : removeCount;
  const len = length - removeCount;
  for (i = startIdx; i < len; ++i) {
    arr[i] = arr[i + removeCount];
  }
  arr.length = len;
}

// scripts/folia/node_modules/pixi.js/lib/scene/container/container-mixins/childrenHelperMixin.mjs
var childrenHelperMixin = {
  allowChildren: true,
  removeChildren(beginIndex = 0, endIndex) {
    const end = endIndex ?? this.children.length;
    const range = end - beginIndex;
    const removed = [];
    if (range > 0 && range <= end) {
      for (let i = end - 1; i >= beginIndex; i--) {
        const child = this.children[i];
        if (!child) continue;
        removed.push(child);
        child.parent = null;
      }
      removeItems(this.children, beginIndex, end);
      const renderGroup = this.renderGroup || this.parentRenderGroup;
      if (renderGroup) {
        renderGroup.removeChildren(removed);
      }
      for (let i = 0; i < removed.length; ++i) {
        const child = removed[i];
        child.parentRenderLayer?.detach(child);
        this.emit("childRemoved", child, this, i);
        removed[i].emit("removed", this);
      }
      if (removed.length > 0) {
        this._didViewChangeTick++;
      }
      return removed;
    } else if (range === 0 && this.children.length === 0) {
      return removed;
    }
    throw new RangeError("removeChildren: numeric values are outside the acceptable range.");
  },
  removeChildAt(index) {
    const child = this.getChildAt(index);
    return this.removeChild(child);
  },
  getChildAt(index) {
    if (index < 0 || index >= this.children.length) {
      throw new Error(`getChildAt: Index (${index}) does not exist.`);
    }
    return this.children[index];
  },
  setChildIndex(child, index) {
    if (index < 0 || index >= this.children.length) {
      throw new Error(`The index ${index} supplied is out of bounds ${this.children.length}`);
    }
    this.getChildIndex(child);
    this.addChildAt(child, index);
  },
  getChildIndex(child) {
    const index = this.children.indexOf(child);
    if (index === -1) {
      throw new Error("The supplied Container must be a child of the caller");
    }
    return index;
  },
  addChildAt(child, index) {
    if (!this.allowChildren) {
      deprecation(v8_0_0, "addChildAt: Only Containers will be allowed to add children in v8.0.0");
    }
    const { children } = this;
    if (index < 0 || index > children.length) {
      throw new Error(`${child}addChildAt: The index ${index} supplied is out of bounds ${children.length}`);
    }
    const sameParent = child.parent === this;
    if (child.parent) {
      const currentIndex = child.parent.children.indexOf(child);
      if (sameParent) {
        if (currentIndex === index) {
          return child;
        }
        child.parent.children.splice(currentIndex, 1);
      } else {
        child.removeFromParent();
      }
    }
    if (index === children.length) {
      children.push(child);
    } else {
      children.splice(index, 0, child);
    }
    const renderGroup = this.renderGroup || this.parentRenderGroup;
    if (this.sortableChildren) this.sortDirty = true;
    if (sameParent) {
      if (renderGroup) {
        renderGroup.structureDidChange = true;
      }
      return child;
    }
    child.parent = this;
    child.didChange = true;
    child._updateFlags = 15;
    if (renderGroup) {
      renderGroup.addChild(child);
    }
    this.emit("childAdded", child, this, index);
    child.emit("added", this);
    return child;
  },
  swapChildren(child, child2) {
    if (child === child2) {
      return;
    }
    const index1 = this.getChildIndex(child);
    const index2 = this.getChildIndex(child2);
    this.children[index1] = child2;
    this.children[index2] = child;
    const renderGroup = this.renderGroup || this.parentRenderGroup;
    if (renderGroup) {
      renderGroup.structureDidChange = true;
    }
    this._didContainerChangeTick++;
  },
  removeFromParent() {
    this.parent?.removeChild(this);
  },
  reparentChild(...child) {
    if (child.length === 1) {
      return this.reparentChildAt(child[0], this.children.length);
    }
    child.forEach((c) => this.reparentChildAt(c, this.children.length));
    return child[0];
  },
  reparentChildAt(child, index) {
    if (child.parent === this) {
      this.setChildIndex(child, index);
      return child;
    }
    const childMat = child.worldTransform.clone();
    child.removeFromParent();
    this.addChildAt(child, index);
    const newMatrix = this.worldTransform.clone();
    newMatrix.invert();
    childMat.prepend(newMatrix);
    child.setFromMatrix(childMat);
    return child;
  },
  replaceChild(oldChild, newChild) {
    oldChild.updateLocalTransform();
    this.addChildAt(newChild, this.getChildIndex(oldChild));
    newChild.setFromMatrix(oldChild.localTransform);
    newChild.updateLocalTransform();
    this.removeChild(oldChild);
  }
};

// scripts/folia/node_modules/pixi.js/lib/scene/container/container-mixins/collectRenderablesMixin.mjs
var collectRenderablesMixin = {
  collectRenderables(instructionSet, renderer, currentLayer) {
    if (this.parentRenderLayer && this.parentRenderLayer !== currentLayer || this.globalDisplayStatus < 7 || !this.includeInBuild) return;
    if (this.sortableChildren) {
      this.sortChildren();
    }
    if (this.isSimple) {
      this.collectRenderablesSimple(instructionSet, renderer, currentLayer);
    } else if (this.renderGroup) {
      renderer.renderPipes.renderGroup.addRenderGroup(this.renderGroup, instructionSet);
    } else {
      this.collectRenderablesWithEffects(instructionSet, renderer, currentLayer);
    }
  },
  collectRenderablesSimple(instructionSet, renderer, currentLayer) {
    const children = this.children;
    const length = children.length;
    for (let i = 0; i < length; i++) {
      children[i].collectRenderables(instructionSet, renderer, currentLayer);
    }
  },
  collectRenderablesWithEffects(instructionSet, renderer, currentLayer) {
    const { renderPipes } = renderer;
    for (let i = 0; i < this.effects.length; i++) {
      const effect = this.effects[i];
      const pipe = renderPipes[effect.pipe];
      pipe.push(effect, this, instructionSet);
    }
    this.collectRenderablesSimple(instructionSet, renderer, currentLayer);
    for (let i = this.effects.length - 1; i >= 0; i--) {
      const effect = this.effects[i];
      const pipe = renderPipes[effect.pipe];
      pipe.pop(effect, this, instructionSet);
    }
  }
};

// scripts/folia/node_modules/pixi.js/lib/filters/FilterEffect.mjs
var FilterEffect = class {
  constructor() {
    this.pipe = "filter";
    this.priority = 1;
  }
  destroy() {
    for (let i = 0; i < this.filters.length; i++) {
      this.filters[i].destroy();
    }
    this.filters = null;
    this.filterArea = null;
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/mask/MaskEffectManager.mjs
var MaskEffectManagerClass = class {
  constructor() {
    this._effectClasses = [];
    this._tests = [];
    this._initialized = false;
  }
  init() {
    if (this._initialized) return;
    this._initialized = true;
    this._effectClasses.forEach((test) => {
      this.add({
        test: test.test,
        maskClass: test
      });
    });
  }
  add(test) {
    this._tests.push(test);
  }
  getMaskEffect(item) {
    if (!this._initialized) this.init();
    for (let i = 0; i < this._tests.length; i++) {
      const test = this._tests[i];
      if (test.test(item)) {
        return BigPool.get(test.maskClass, item);
      }
    }
    return item;
  }
  returnMaskEffect(effect) {
    BigPool.return(effect);
  }
};
var MaskEffectManager = new MaskEffectManagerClass();
extensions.handleByList(ExtensionType.MaskEffect, MaskEffectManager._effectClasses);

// scripts/folia/node_modules/pixi.js/lib/scene/container/container-mixins/effectsMixin.mjs
var effectsMixin = {
  _maskEffect: null,
  _maskOptions: {
    inverse: false,
    channel: "red"
  },
  _filterEffect: null,
  effects: [],
  _markStructureAsChanged() {
    const renderGroup = this.renderGroup || this.parentRenderGroup;
    if (renderGroup) {
      renderGroup.structureDidChange = true;
    }
  },
  addEffect(effect) {
    const index = this.effects.indexOf(effect);
    if (index !== -1) return;
    this.effects.push(effect);
    this.effects.sort((a, b) => a.priority - b.priority);
    this._markStructureAsChanged();
    this._updateIsSimple();
  },
  removeEffect(effect) {
    const index = this.effects.indexOf(effect);
    if (index === -1) return;
    this.effects.splice(index, 1);
    this._markStructureAsChanged();
    this._updateIsSimple();
  },
  set mask(value) {
    const effect = this._maskEffect;
    if (effect?.mask === value) return;
    if (effect) {
      this.removeEffect(effect);
      MaskEffectManager.returnMaskEffect(effect);
      this._maskEffect = null;
    }
    if (value === null || value === void 0) return;
    this._maskEffect = MaskEffectManager.getMaskEffect(value);
    this.addEffect(this._maskEffect);
  },
  get mask() {
    return this._maskEffect?.mask;
  },
  setMask(options) {
    this._maskOptions = {
      ...this._maskOptions,
      ...options
    };
    if (options.mask) {
      this.mask = options.mask;
    }
    this._markStructureAsChanged();
  },
  set filters(value) {
    if (!Array.isArray(value) && value) value = [value];
    const effect = this._filterEffect || (this._filterEffect = new FilterEffect());
    value = value;
    const hasFilters = value?.length > 0;
    const hadFilters = effect.filters?.length > 0;
    const didChange = hasFilters !== hadFilters;
    value = Array.isArray(value) ? value.slice(0) : value;
    effect.filters = Object.freeze(value);
    if (didChange) {
      if (hasFilters) {
        this.addEffect(effect);
      } else {
        this.removeEffect(effect);
        effect.filters = value ?? null;
      }
    }
  },
  get filters() {
    return this._filterEffect?.filters;
  },
  set filterArea(value) {
    this._filterEffect || (this._filterEffect = new FilterEffect());
    this._filterEffect.filterArea = value;
  },
  get filterArea() {
    return this._filterEffect?.filterArea;
  }
};

// scripts/folia/node_modules/pixi.js/lib/scene/container/container-mixins/findMixin.mjs
var findMixin = {
  label: null,
  get name() {
    deprecation(v8_0_0, "Container.name property has been removed, use Container.label instead");
    return this.label;
  },
  set name(value) {
    deprecation(v8_0_0, "Container.name property has been removed, use Container.label instead");
    this.label = value;
  },
  getChildByName(name, deep = false) {
    return this.getChildByLabel(name, deep);
  },
  getChildByLabel(label, deep = false) {
    const children = this.children;
    for (let i = 0; i < children.length; i++) {
      const child = children[i];
      if (child.label === label || label instanceof RegExp && label.test(child.label)) return child;
    }
    if (deep) {
      for (let i = 0; i < children.length; i++) {
        const child = children[i];
        const found = child.getChildByLabel(label, true);
        if (found) {
          return found;
        }
      }
    }
    return null;
  },
  getChildrenByLabel(label, deep = false, out = []) {
    const children = this.children;
    for (let i = 0; i < children.length; i++) {
      const child = children[i];
      if (child.label === label || label instanceof RegExp && label.test(child.label)) {
        out.push(child);
      }
    }
    if (deep) {
      for (let i = 0; i < children.length; i++) {
        children[i].getChildrenByLabel(label, true, out);
      }
    }
    return out;
  }
};

// scripts/folia/node_modules/pixi.js/lib/scene/container/bounds/utils/matrixAndBoundsPool.mjs
var matrixPool = BigPool.getPool(Matrix);
var boundsPool = BigPool.getPool(Bounds);

// scripts/folia/node_modules/pixi.js/lib/scene/container/container-mixins/getFastGlobalBoundsMixin.mjs
var tempMatrix = new Matrix();
var getFastGlobalBoundsMixin = {
  getFastGlobalBounds(factorRenderLayers, bounds) {
    bounds || (bounds = new Bounds());
    bounds.clear();
    this._getGlobalBoundsRecursive(!!factorRenderLayers, bounds, this.parentRenderLayer);
    if (!bounds.isValid) {
      bounds.set(0, 0, 0, 0);
    }
    const renderGroup = this.renderGroup || this.parentRenderGroup;
    bounds.applyMatrix(renderGroup.worldTransform);
    return bounds;
  },
  _getGlobalBoundsRecursive(factorRenderLayers, bounds, currentLayer) {
    let localBounds = bounds;
    if (factorRenderLayers && this.parentRenderLayer && this.parentRenderLayer !== currentLayer) return;
    if (this.localDisplayStatus !== 7 || !this.measurable) {
      return;
    }
    const manageEffects = !!this.effects.length;
    if (this.renderGroup || manageEffects) {
      localBounds = boundsPool.get().clear();
    }
    if (this.boundsArea) {
      bounds.addRect(this.boundsArea, this.worldTransform);
    } else {
      if (this.renderPipeId) {
        const viewBounds = this.bounds;
        localBounds.addFrame(
          viewBounds.minX,
          viewBounds.minY,
          viewBounds.maxX,
          viewBounds.maxY,
          this.groupTransform
        );
      }
      const children = this.children;
      for (let i = 0; i < children.length; i++) {
        children[i]._getGlobalBoundsRecursive(factorRenderLayers, localBounds, currentLayer);
      }
    }
    if (manageEffects) {
      let advanced = false;
      const renderGroup = this.renderGroup || this.parentRenderGroup;
      for (let i = 0; i < this.effects.length; i++) {
        if (this.effects[i].addBounds) {
          if (!advanced) {
            advanced = true;
            localBounds.applyMatrix(renderGroup.worldTransform);
          }
          this.effects[i].addBounds(localBounds, true);
        }
      }
      if (advanced) {
        localBounds.applyMatrix(renderGroup.worldTransform.copyTo(tempMatrix).invert());
      }
      bounds.addBounds(localBounds);
      boundsPool.return(localBounds);
    } else if (this.renderGroup) {
      bounds.addBounds(localBounds, this.relativeGroupTransform);
      boundsPool.return(localBounds);
    }
  }
};

// scripts/folia/node_modules/pixi.js/lib/scene/container/bounds/getGlobalBounds.mjs
function getGlobalBounds(target, skipUpdateTransform, bounds) {
  bounds.clear();
  let parentTransform;
  let pooledMatrix;
  if (target.parent) {
    if (!skipUpdateTransform) {
      pooledMatrix = matrixPool.get().identity();
      parentTransform = updateTransformBackwards(target, pooledMatrix);
    } else {
      parentTransform = target.parent.worldTransform;
    }
  } else {
    parentTransform = Matrix.IDENTITY;
  }
  _getGlobalBounds(target, bounds, parentTransform, skipUpdateTransform);
  if (pooledMatrix) {
    matrixPool.return(pooledMatrix);
  }
  if (!bounds.isValid) {
    bounds.set(0, 0, 0, 0);
  }
  return bounds;
}
function _getGlobalBounds(target, bounds, parentTransform, skipUpdateTransform) {
  if (!target.visible || !target.measurable) return;
  let worldTransform;
  if (!skipUpdateTransform) {
    target.updateLocalTransform();
    worldTransform = matrixPool.get();
    worldTransform.appendFrom(target.localTransform, parentTransform);
  } else {
    worldTransform = target.worldTransform;
  }
  const parentBounds = bounds;
  const preserveBounds = !!target.effects.length;
  if (preserveBounds) {
    bounds = boundsPool.get().clear();
  }
  if (target.boundsArea) {
    bounds.addRect(target.boundsArea, worldTransform);
  } else {
    const renderableBounds = target.bounds;
    if (renderableBounds && !renderableBounds.isEmpty()) {
      bounds.matrix = worldTransform;
      bounds.addBounds(renderableBounds);
    }
    for (let i = 0; i < target.children.length; i++) {
      _getGlobalBounds(target.children[i], bounds, worldTransform, skipUpdateTransform);
    }
  }
  if (preserveBounds) {
    for (let i = 0; i < target.effects.length; i++) {
      target.effects[i].addBounds?.(bounds);
    }
    parentBounds.addBounds(bounds, Matrix.IDENTITY);
    boundsPool.return(bounds);
  }
  if (!skipUpdateTransform) {
    matrixPool.return(worldTransform);
  }
}
function updateTransformBackwards(target, parentTransform) {
  const parent = target.parent;
  if (parent) {
    updateTransformBackwards(parent, parentTransform);
    parent.updateLocalTransform();
    parentTransform.append(parent.localTransform);
  }
  return parentTransform;
}

// scripts/folia/node_modules/pixi.js/lib/scene/container/utils/multiplyColors.mjs
var WHITE_BGR = 16777215;
function multiplyColors(localBGRColor, parentBGRColor) {
  if (localBGRColor === WHITE_BGR) {
    return parentBGRColor;
  }
  if (parentBGRColor === WHITE_BGR) {
    return localBGRColor;
  }
  return multiplyHexColors(localBGRColor, parentBGRColor);
}

// scripts/folia/node_modules/pixi.js/lib/scene/container/container-mixins/getGlobalMixin.mjs
function bgr2rgb(color) {
  return ((color & 255) << 16) + (color & 65280) + (color >> 16 & 255);
}
var getGlobalMixin = {
  getGlobalAlpha(skipUpdate) {
    if (skipUpdate) {
      if (this.renderGroup) {
        return this.renderGroup.worldAlpha;
      }
      if (this.parentRenderGroup) {
        return this.parentRenderGroup.worldAlpha * this.alpha;
      }
      return this.alpha;
    }
    let alpha = this.alpha;
    let current = this.parent;
    while (current) {
      alpha *= current.alpha;
      current = current.parent;
    }
    return alpha;
  },
  getGlobalTransform(matrix = new Matrix(), skipUpdate) {
    if (skipUpdate) {
      return matrix.copyFrom(this.worldTransform);
    }
    this.updateLocalTransform();
    const parentTransform = updateTransformBackwards(this, matrixPool.get().identity());
    matrix.appendFrom(this.localTransform, parentTransform);
    matrixPool.return(parentTransform);
    return matrix;
  },
  getGlobalTint(skipUpdate) {
    if (skipUpdate) {
      if (this.renderGroup) {
        return bgr2rgb(this.renderGroup.worldColor);
      }
      if (this.parentRenderGroup) {
        return bgr2rgb(
          multiplyColors(this.localColor, this.parentRenderGroup.worldColor)
        );
      }
      return this.tint;
    }
    let color = this.localColor;
    let parent = this.parent;
    while (parent) {
      color = multiplyColors(color, parent.localColor);
      parent = parent.parent;
    }
    return bgr2rgb(color);
  }
};

// scripts/folia/node_modules/pixi.js/lib/scene/container/bounds/getLocalBounds.mjs
function getLocalBounds(target, bounds, relativeMatrix) {
  bounds.clear();
  relativeMatrix || (relativeMatrix = Matrix.IDENTITY);
  _getLocalBounds(target, bounds, relativeMatrix, target, true);
  if (!bounds.isValid) {
    bounds.set(0, 0, 0, 0);
  }
  return bounds;
}
function _getLocalBounds(target, bounds, parentTransform, rootContainer, isRoot) {
  let relativeTransform;
  if (!isRoot) {
    if (!target.visible || !target.measurable) return;
    target.updateLocalTransform();
    const localTransform = target.localTransform;
    relativeTransform = matrixPool.get();
    relativeTransform.appendFrom(localTransform, parentTransform);
  } else {
    relativeTransform = matrixPool.get();
    relativeTransform = parentTransform.copyTo(relativeTransform);
  }
  const parentBounds = bounds;
  const preserveBounds = !!target.effects.length;
  if (preserveBounds) {
    bounds = boundsPool.get().clear();
  }
  if (target.boundsArea) {
    bounds.addRect(target.boundsArea, relativeTransform);
  } else {
    if (target.renderPipeId) {
      bounds.matrix = relativeTransform;
      bounds.addBounds(target.bounds);
    }
    const children = target.children;
    for (let i = 0; i < children.length; i++) {
      _getLocalBounds(children[i], bounds, relativeTransform, rootContainer, false);
    }
  }
  if (preserveBounds) {
    for (let i = 0; i < target.effects.length; i++) {
      target.effects[i].addLocalBounds?.(bounds, rootContainer);
    }
    parentBounds.addBounds(bounds, Matrix.IDENTITY);
    boundsPool.return(bounds);
  }
  matrixPool.return(relativeTransform);
}

// scripts/folia/node_modules/pixi.js/lib/scene/container/utils/checkChildrenDidChange.mjs
function checkChildrenDidChange(container, previousData) {
  const children = container.children;
  for (let i = 0; i < children.length; i++) {
    const child = children[i];
    const uid2 = child.uid;
    const didChange = (child._didViewChangeTick & 65535) << 16 | child._didContainerChangeTick & 65535;
    const index = previousData.index;
    if (previousData.data[index] !== uid2 || previousData.data[index + 1] !== didChange) {
      previousData.data[previousData.index] = uid2;
      previousData.data[previousData.index + 1] = didChange;
      previousData.didChange = true;
    }
    previousData.index = index + 2;
    if (child.children.length) {
      checkChildrenDidChange(child, previousData);
    }
  }
  return previousData.didChange;
}

// scripts/folia/node_modules/pixi.js/lib/scene/container/container-mixins/measureMixin.mjs
var tempMatrix2 = new Matrix();
var measureMixin = {
  _localBoundsCacheId: -1,
  _localBoundsCacheData: null,
  _setWidth(value, localWidth) {
    const sign = Math.sign(this.scale.x) || 1;
    if (localWidth !== 0) {
      this.scale.x = value / localWidth * sign;
    } else {
      this.scale.x = sign;
    }
  },
  _setHeight(value, localHeight) {
    const sign = Math.sign(this.scale.y) || 1;
    if (localHeight !== 0) {
      this.scale.y = value / localHeight * sign;
    } else {
      this.scale.y = sign;
    }
  },
  getLocalBounds() {
    if (!this._localBoundsCacheData) {
      this._localBoundsCacheData = {
        data: [],
        index: 1,
        didChange: false,
        localBounds: new Bounds()
      };
    }
    const localBoundsCacheData = this._localBoundsCacheData;
    localBoundsCacheData.index = 1;
    localBoundsCacheData.didChange = false;
    if (localBoundsCacheData.data[0] !== this._didViewChangeTick) {
      localBoundsCacheData.didChange = true;
      localBoundsCacheData.data[0] = this._didViewChangeTick;
    }
    checkChildrenDidChange(this, localBoundsCacheData);
    if (localBoundsCacheData.didChange) {
      getLocalBounds(this, localBoundsCacheData.localBounds, tempMatrix2);
    }
    return localBoundsCacheData.localBounds;
  },
  getBounds(skipUpdate, bounds) {
    return getGlobalBounds(this, skipUpdate, bounds || new Bounds());
  }
};

// scripts/folia/node_modules/pixi.js/lib/scene/container/container-mixins/onRenderMixin.mjs
var onRenderMixin = {
  _onRender: null,
  set onRender(func) {
    const renderGroup = this.renderGroup || this.parentRenderGroup;
    if (!func) {
      if (this._onRender) {
        renderGroup?.removeOnRender(this);
      }
      this._onRender = null;
      return;
    }
    if (!this._onRender) {
      renderGroup?.addOnRender(this);
    }
    this._onRender = func;
  },
  get onRender() {
    return this._onRender;
  }
};

// scripts/folia/node_modules/pixi.js/lib/scene/container/container-mixins/sortMixin.mjs
var sortMixin = {
  _zIndex: 0,
  sortDirty: false,
  sortableChildren: false,
  get zIndex() {
    return this._zIndex;
  },
  set zIndex(value) {
    if (this._zIndex === value) return;
    this._zIndex = value;
    this.depthOfChildModified();
  },
  depthOfChildModified() {
    if (this.parent) {
      this.parent.sortableChildren = true;
      this.parent.sortDirty = true;
    }
    if (this.parentRenderGroup) {
      this.parentRenderGroup.structureDidChange = true;
    }
  },
  sortChildren() {
    if (!this.sortDirty) return;
    this.sortDirty = false;
    this.children.sort(sortChildren);
  }
};
function sortChildren(a, b) {
  return a._zIndex - b._zIndex;
}

// scripts/folia/node_modules/pixi.js/lib/scene/container/container-mixins/toLocalGlobalMixin.mjs
var toLocalGlobalMixin = {
  getGlobalPosition(point = new Point(), skipUpdate = false) {
    if (this.parent) {
      this.parent.toGlobal(this._position, point, skipUpdate);
    } else {
      point.x = this._position.x;
      point.y = this._position.y;
    }
    return point;
  },
  toGlobal(position, point, skipUpdate = false) {
    const globalMatrix = this.getGlobalTransform(matrixPool.get(), skipUpdate);
    point = globalMatrix.apply(position, point);
    matrixPool.return(globalMatrix);
    return point;
  },
  toLocal(position, from, point, skipUpdate) {
    if (from) {
      position = from.toGlobal(position, point, skipUpdate);
    }
    const globalMatrix = this.getGlobalTransform(matrixPool.get(), skipUpdate);
    point = globalMatrix.applyInverse(position, point);
    matrixPool.return(globalMatrix);
    return point;
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/shared/texture/TexturePool.mjs
var count = 0;
var maxKeyDimension = 32767;
var scaleBit = 4294967296;
var formatBit = 8589934592;
var formatIds = /* @__PURE__ */ Object.create(null);
var nextFormatId = 0;
function formatId(format) {
  const id = formatIds[format];
  if (id !== void 0) return id;
  return formatIds[format] = nextFormatId++;
}
function bucketKey(width, height, antialias, autoGenerateMipmaps, format, scaleMode) {
  const packed = (width << 17) + (height << 2) + ((autoGenerateMipmaps ? 1 : 0) << 1) + (antialias ? 1 : 0);
  const scale = scaleMode === "nearest" ? 1 : 0;
  return packed + scale * scaleBit + formatId(format) * formatBit;
}
var TexturePoolClass = class {
  /**
   * @param textureOptions - options that will be passed to BaseRenderTexture constructor
   * @param {SCALE_MODE} [textureOptions.scaleMode] - See {@link SCALE_MODE} for possible values.
   */
  constructor(textureOptions) {
    this._buckets = /* @__PURE__ */ new Map();
    this._poolKey = /* @__PURE__ */ Object.create(null);
    this._poolStyle = /* @__PURE__ */ Object.create(null);
    this._screens = new ScreenSizeRegistry();
    this._enableFullScreen = false;
    this.textureOptions = textureOptions || {};
  }
  /**
   * A style built from the pool options. The pool no longer applies it to anything.
   * @deprecated since 8.21.0, pooled textures carry their own style; pass `scaleMode` in the request instead.
   */
  get textureStyle() {
    deprecation(v8_21_0, "TexturePool.textureStyle is no longer used, pooled textures carry their own style. Pass scaleMode in the request instead.");
    if (!this._textureStyle) this._textureStyle = new TextureStyle(this.textureOptions);
    return this._textureStyle;
  }
  set textureStyle(value) {
    deprecation(v8_21_0, "TexturePool.textureStyle is no longer used, pooled textures carry their own style. Pass scaleMode in the request instead.");
    this._textureStyle = value;
  }
  /**
   * Has no effect. The pool sizes textures to the screens registered with
   * {@link TexturePoolClass#setScreenSize|setScreenSize}.
   * @deprecated since 8.21.0
   */
  get enableFullScreen() {
    deprecation(v8_21_0, "TexturePool.enableFullScreen is no longer used, the pool sizes textures to the screens registered with setScreenSize.");
    return this._enableFullScreen;
  }
  set enableFullScreen(value) {
    deprecation(v8_21_0, "TexturePool.enableFullScreen is no longer used, the pool sizes textures to the screens registered with setScreenSize.");
    this._enableFullScreen = value;
  }
  createTexture(...args) {
    let options = args[0];
    if (typeof options === "number") {
      deprecation(v8_21_0, "TexturePool.createTexture params are now an options object. See params: { width, height, antialias, autoGenerateMipmaps }");
      options = {
        width: options,
        height: args[1],
        antialias: args[2] ?? false,
        autoGenerateMipmaps: args[3] ?? false
      };
    }
    const format = options.format ?? this.textureOptions.format ?? TextureSource.defaultOptions.format;
    const scaleMode = options.scaleMode ?? this.textureOptions.scaleMode ?? TextureStyle.defaultOptions.scaleMode;
    const textureSource = new TextureSource({
      ...this.textureOptions,
      width: options.width,
      height: options.height,
      resolution: 1,
      antialias: options.antialias ?? false,
      autoGarbageCollect: false,
      autoGenerateMipmaps: options.autoGenerateMipmaps ?? false,
      format,
      scaleMode
    });
    return new Texture({
      source: textureSource,
      label: `texturePool_${count++}`
    });
  }
  getOptimalTexture(...args) {
    let options = args[0];
    if (typeof options === "number") {
      deprecation(v8_21_0, "TexturePool.getOptimalTexture params are now an options object. See params: { width, height, resolution, antialias, autoGenerateMipmaps }");
      options = {
        width: options,
        height: args[1],
        resolution: args[2] ?? 1,
        antialias: args[3] ?? false,
        autoGenerateMipmaps: args[4] ?? false
      };
    }
    const frameWidth = options.width;
    const frameHeight = options.height;
    const resolution = options.resolution ?? 1;
    const antialias = options.antialias ?? false;
    const autoGenerateMipmaps = options.autoGenerateMipmaps ?? false;
    const format = options.format ?? this.textureOptions.format ?? TextureSource.defaultOptions.format;
    const scaleMode = options.scaleMode ?? this.textureOptions.scaleMode ?? TextureStyle.defaultOptions.scaleMode;
    const { width: textureWidth, height: textureHeight } = this.getOptimalSize(
      frameWidth,
      frameHeight,
      resolution
    );
    if (textureWidth > maxKeyDimension || textureHeight > maxKeyDimension) {
      warn(`TexturePool: ${textureWidth}x${textureHeight} is larger than the ${maxKeyDimension}px pool key limit, textures of this size may be pooled together`);
    }
    const key = bucketKey(textureWidth, textureHeight, antialias, autoGenerateMipmaps, format, scaleMode);
    let bucket = this._buckets.get(key);
    if (!bucket) {
      bucket = [];
      this._buckets.set(key, bucket);
    }
    let texture = bucket.pop();
    if (!texture) {
      texture = this.createTexture({
        width: textureWidth,
        height: textureHeight,
        antialias,
        autoGenerateMipmaps,
        format,
        scaleMode
      });
      this._poolStyle[texture.uid] = texture.source.style;
    }
    texture.source._resolution = resolution;
    texture.source.width = textureWidth / resolution;
    texture.source.height = textureHeight / resolution;
    texture.source.pixelWidth = textureWidth;
    texture.source.pixelHeight = textureHeight;
    texture.frame.x = 0;
    texture.frame.y = 0;
    texture.frame.width = frameWidth;
    texture.frame.height = frameHeight;
    texture.updateUvs();
    this._poolKey[texture.uid] = key;
    return texture;
  }
  /**
   * The backing size, in physical pixels, that {@link TexturePoolClass#getOptimalTexture|getOptimalTexture}
   * would allocate for a request, without taking a texture from the pool.
   *
   * Each axis is the next power of two, or the smallest registered screen the request fits inside
   * (see {@link TexturePoolClass#setScreenSize|setScreenSize}). Use it when a consumer needs to know
   * where a request's content will sit inside its pooled texture before it has one, such as a uniform
   * that maps content space onto texture space.
   * @param frameWidth - The minimum width of the texture.
   * @param frameHeight - The minimum height of the texture.
   * @param resolution - The resolution of the texture.
   * @returns The width and height the pooled texture would have, in physical pixels.
   */
  getOptimalSize(frameWidth, frameHeight, resolution = 1) {
    const pixelWidth = Math.ceil(frameWidth * resolution - 1e-6);
    const pixelHeight = Math.ceil(frameHeight * resolution - 1e-6);
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
   * Gets a pooled texture matching the dimensions and resolution of the given texture.
   *
   * This is a convenience wrapper around {@link TexturePoolClass#getOptimalTexture|getOptimalTexture}
   * that copies width, height, and resolution from an existing texture. Useful when a filter needs
   * a temporary texture the same size as its input (e.g., for multi-pass blur).
   * @param texture - The texture whose dimensions to match.
   * @param antialias - Whether to use antialias on the pooled texture. Defaults to `false`.
   * @returns A pooled texture with power-of-two or screen sized backing dimensions at the source resolution.
   */
  getSameSizeTexture(texture, antialias = false) {
    const source = texture.source;
    return this.getOptimalTexture({
      width: texture.width,
      height: texture.height,
      resolution: source._resolution,
      antialias
    });
  }
  /**
   * Returns a texture to the pool so it can be reused by future
   * {@link TexturePoolClass#getOptimalTexture|getOptimalTexture}
   * or {@link TexturePoolClass#getSameSizeTexture|getSameSizeTexture} calls.
   *
   * If you gave the texture a style of your own after obtaining it (a different address mode, anisotropy
   * or similar), pass `resetStyle = true` so the pool puts its own style back. Otherwise your style stays
   * on the texture and the next consumer inherits it.
   * @param renderTexture - The texture to return to the pool.
   * @param resetStyle - When `true`, restores the style the pool created for this texture. Defaults to `false`.
   */
  returnTexture(renderTexture, resetStyle = false) {
    const uid2 = renderTexture.uid;
    const key = this._poolKey[uid2];
    if (key === void 0) {
      warn("TexturePool: returnTexture was passed a texture that did not come from this pool, ignoring it");
      return;
    }
    const poolStyle = this._poolStyle[uid2];
    if (resetStyle && renderTexture.source.style !== poolStyle) {
      renderTexture.source.style = poolStyle;
    }
    const textures = this._buckets.get(key);
    if (!textures) {
      delete this._poolKey[uid2];
      delete this._poolStyle[uid2];
      renderTexture.destroy(true);
      return;
    }
    textures.push(renderTexture);
  }
  /**
   * Registers the screen size of a renderer with the pool, in physical pixels.
   *
   * While a screen is registered, a request that fits inside it on an axis is given that screen's size on
   * that axis instead of the next power of two, which stops a full screen filter from allocating a texture
   * far larger than the screen. Requests larger than every registered screen on an axis keep the power of
   * two size - the pool never rounds a request up to a screen it does not fit in.
   * @param rendererUid - The uid of the renderer, used to update or remove this screen later.
   * @param pixelWidth - The width of the screen in physical pixels.
   * @param pixelHeight - The height of the screen in physical pixels.
   */
  setScreenSize(rendererUid, pixelWidth, pixelHeight) {
    if (!this._screens.set(rendererUid, pixelWidth, pixelHeight)) return;
    this._pruneScreenTextures();
  }
  /**
   * Removes a screen previously registered with
   * {@link TexturePoolClass#setScreenSize|setScreenSize}, destroying any idle textures that were
   * only being kept for it.
   * @param rendererUid - The uid the screen was registered with.
   */
  removeScreen(rendererUid) {
    if (!this._screens.remove(rendererUid)) return;
    this._pruneScreenTextures();
  }
  /**
   * Destroys the idle textures in every bucket that has a non power of two dimension matching no live
   * screen. Power of two buckets are always kept, as any request can fall back to them.
   */
  _pruneScreenTextures() {
    for (const [key, textures] of this._buckets) {
      const packed = key >>> 0;
      const width = packed >>> 17;
      const height = packed >>> 2 & 32767;
      if ((isPow2(width) || this._screens.hasWidth(width)) && (isPow2(height) || this._screens.hasHeight(height))) continue;
      this._dropTextures(textures, true);
      this._buckets.delete(key);
    }
  }
  /**
   * Forgets idle textures were ever handed out, so a later return is ignored, and optionally destroys them.
   * @param textures - The textures of one bucket.
   * @param destroy - Whether to destroy the textures as well.
   */
  _dropTextures(textures, destroy) {
    for (let i = 0; i < textures.length; i++) {
      const texture = textures[i];
      delete this._poolKey[texture.uid];
      delete this._poolStyle[texture.uid];
      if (destroy) texture.destroy(true);
    }
  }
  /**
   * Clears the pool.
   * @param destroyTextures - Destroy all stored textures.
   */
  clear(destroyTextures) {
    for (const textures of this._buckets.values()) {
      this._dropTextures(textures, destroyTextures !== false);
    }
    this._buckets.clear();
  }
};
var TexturePool = new TexturePoolClass();
GlobalResourceRegistry.register(TexturePool);

// scripts/folia/node_modules/pixi.js/lib/scene/container/RenderGroup.mjs
var RenderGroup = class {
  constructor() {
    this.renderPipeId = "renderGroup";
    this.root = null;
    this.canBundle = false;
    this.renderGroupParent = null;
    this.renderGroupChildren = [];
    this.worldTransform = new Matrix();
    this.worldColorAlpha = 4294967295;
    this.worldColor = 16777215;
    this.worldAlpha = 1;
    this.childrenToUpdate = /* @__PURE__ */ Object.create(null);
    this.updateTick = 0;
    this.gcTick = 0;
    this.childrenRenderablesToUpdate = { list: [], index: 0 };
    this.structureDidChange = true;
    this.instructionSet = new InstructionSet();
    this._onRenderContainers = [];
    this.textureNeedsUpdate = true;
    this.isCachedAsTexture = false;
    this._matrixDirty = 7;
  }
  init(root) {
    this.root = root;
    if (root._onRender) this.addOnRender(root);
    root.didChange = true;
    const children = root.children;
    for (let i = 0; i < children.length; i++) {
      const child = children[i];
      child._updateFlags = 15;
      this.addChild(child);
    }
  }
  enableCacheAsTexture(options = {}) {
    this.textureOptions = options;
    this.isCachedAsTexture = true;
    this.textureNeedsUpdate = true;
  }
  disableCacheAsTexture() {
    this.isCachedAsTexture = false;
    if (this.texture) {
      TexturePool.returnTexture(this.texture);
      this.texture = null;
    }
  }
  updateCacheTexture() {
    this.textureNeedsUpdate = true;
    const cachedParent = this._parentCacheAsTextureRenderGroup;
    if (cachedParent && !cachedParent.textureNeedsUpdate) {
      cachedParent.updateCacheTexture();
    }
  }
  reset() {
    this.renderGroupChildren.length = 0;
    for (const i in this.childrenToUpdate) {
      const childrenAtDepth = this.childrenToUpdate[i];
      childrenAtDepth.list.fill(null);
      childrenAtDepth.index = 0;
    }
    this.childrenRenderablesToUpdate.index = 0;
    this.childrenRenderablesToUpdate.list.fill(null);
    this.root = null;
    this.updateTick = 0;
    this.structureDidChange = true;
    this._onRenderContainers.length = 0;
    this.renderGroupParent = null;
    this.disableCacheAsTexture();
  }
  get localTransform() {
    return this.root.localTransform;
  }
  addRenderGroupChild(renderGroupChild) {
    if (renderGroupChild.renderGroupParent) {
      renderGroupChild.renderGroupParent._removeRenderGroupChild(renderGroupChild);
    }
    renderGroupChild.renderGroupParent = this;
    this.renderGroupChildren.push(renderGroupChild);
  }
  _removeRenderGroupChild(renderGroupChild) {
    const index = this.renderGroupChildren.indexOf(renderGroupChild);
    if (index > -1) {
      this.renderGroupChildren.splice(index, 1);
    }
    renderGroupChild.renderGroupParent = null;
  }
  addChild(child) {
    this.structureDidChange = true;
    child.parentRenderGroup = this;
    child.updateTick = -1;
    if (child.parent === this.root) {
      child.relativeRenderGroupDepth = 1;
    } else {
      child.relativeRenderGroupDepth = child.parent.relativeRenderGroupDepth + 1;
    }
    child.didChange = true;
    this.onChildUpdate(child);
    if (child.renderGroup) {
      this.addRenderGroupChild(child.renderGroup);
      return;
    }
    if (child._onRender) this.addOnRender(child);
    const children = child.children;
    for (let i = 0; i < children.length; i++) {
      this.addChild(children[i]);
    }
  }
  removeChild(child) {
    this.structureDidChange = true;
    if (child._onRender) {
      if (!child.renderGroup) {
        this.removeOnRender(child);
      }
    }
    child.parentRenderGroup = null;
    if (child.renderGroup) {
      this._removeRenderGroupChild(child.renderGroup);
      return;
    }
    const children = child.children;
    for (let i = 0; i < children.length; i++) {
      this.removeChild(children[i]);
    }
  }
  removeChildren(children) {
    for (let i = 0; i < children.length; i++) {
      this.removeChild(children[i]);
    }
  }
  onChildUpdate(child) {
    let childrenToUpdate = this.childrenToUpdate[child.relativeRenderGroupDepth];
    if (!childrenToUpdate) {
      childrenToUpdate = this.childrenToUpdate[child.relativeRenderGroupDepth] = {
        index: 0,
        list: []
      };
    }
    childrenToUpdate.list[childrenToUpdate.index++] = child;
  }
  updateRenderable(renderable) {
    if (renderable.globalDisplayStatus < 7) return;
    this.instructionSet.renderPipes[renderable.renderPipeId].updateRenderable(renderable);
    renderable.didViewUpdate = false;
  }
  onChildViewUpdate(child) {
    this.childrenRenderablesToUpdate.list[this.childrenRenderablesToUpdate.index++] = child;
  }
  get isRenderable() {
    return this.root.localDisplayStatus === 7 && this.worldAlpha > 0;
  }
  /**
   * adding a container to the onRender list will make sure the user function
   * passed in to the user defined 'onRender` callBack
   * @param container - the container to add to the onRender list
   */
  addOnRender(container) {
    if (this._onRenderContainers.indexOf(container) === -1) {
      this._onRenderContainers.push(container);
    }
  }
  removeOnRender(container) {
    const idx = this._onRenderContainers.indexOf(container);
    if (idx !== -1) this._onRenderContainers.splice(idx, 1);
  }
  runOnRender(renderer) {
    for (let i = 0; i < this._onRenderContainers.length; i++) {
      this._onRenderContainers[i]._onRender(renderer);
    }
  }
  destroy() {
    this.disableCacheAsTexture();
    this.renderGroupParent = null;
    this.root = null;
    this.childrenRenderablesToUpdate = null;
    this.childrenToUpdate = null;
    this.renderGroupChildren = null;
    this._onRenderContainers = null;
    this.instructionSet?.destroy();
    this.instructionSet = null;
  }
  getChildren(out = []) {
    const children = this.root.children;
    for (let i = 0; i < children.length; i++) {
      this._getChildren(children[i], out);
    }
    return out;
  }
  _getChildren(container, out = []) {
    out.push(container);
    if (container.renderGroup) return out;
    const children = container.children;
    for (let i = 0; i < children.length; i++) {
      this._getChildren(children[i], out);
    }
    return out;
  }
  invalidateMatrices() {
    this._matrixDirty = 7;
  }
  /**
   * Returns the inverse of the world transform matrix.
   * @returns {Matrix} The inverse of the world transform matrix.
   */
  get inverseWorldTransform() {
    if ((this._matrixDirty & 1) === 0) return this._inverseWorldTransform;
    this._matrixDirty &= ~1;
    this._inverseWorldTransform || (this._inverseWorldTransform = new Matrix());
    return this._inverseWorldTransform.copyFrom(this.worldTransform).invert();
  }
  /**
   * Returns the inverse of the texture offset transform matrix.
   * @returns {Matrix} The inverse of the texture offset transform matrix.
   */
  get textureOffsetInverseTransform() {
    if ((this._matrixDirty & 2) === 0) return this._textureOffsetInverseTransform;
    this._matrixDirty &= ~2;
    this._textureOffsetInverseTransform || (this._textureOffsetInverseTransform = new Matrix());
    return this._textureOffsetInverseTransform.copyFrom(this.inverseWorldTransform).translate(
      -this._textureBounds.x,
      -this._textureBounds.y
    );
  }
  /**
   * Returns the inverse of the parent texture transform matrix.
   * This is used to properly transform coordinates when rendering into cached textures.
   * @returns {Matrix} The inverse of the parent texture transform matrix.
   */
  get inverseParentTextureTransform() {
    if ((this._matrixDirty & 4) === 0) return this._inverseParentTextureTransform;
    this._matrixDirty &= ~4;
    const parentCacheAsTexture = this._parentCacheAsTextureRenderGroup;
    if (parentCacheAsTexture) {
      this._inverseParentTextureTransform || (this._inverseParentTextureTransform = new Matrix());
      return this._inverseParentTextureTransform.copyFrom(this.worldTransform).prepend(parentCacheAsTexture.inverseWorldTransform).translate(
        -parentCacheAsTexture._textureBounds.x,
        -parentCacheAsTexture._textureBounds.y
      );
    }
    return this.worldTransform;
  }
  /**
   * Returns a matrix that transforms coordinates to the correct coordinate space of the texture being rendered to.
   * This is the texture offset inverse transform of the closest parent RenderGroup that is cached as a texture.
   * @returns {Matrix | null} The transform matrix for the cached texture coordinate space,
   * or null if no parent is cached as texture.
   */
  get cacheToLocalTransform() {
    if (this.isCachedAsTexture) {
      return this.textureOffsetInverseTransform;
    }
    if (!this._parentCacheAsTextureRenderGroup) return null;
    return this._parentCacheAsTextureRenderGroup.textureOffsetInverseTransform;
  }
};

// scripts/folia/node_modules/pixi.js/lib/scene/container/utils/assignWithIgnore.mjs
function assignWithIgnore(target, options, ignore = {}) {
  for (const key in options) {
    if (!ignore[key] && options[key] !== void 0) {
      target[key] = options[key];
    }
  }
}

// scripts/folia/node_modules/pixi.js/lib/scene/container/Container.mjs
var defaultSkew = new ObservablePoint(null);
var defaultPivot = new ObservablePoint(null);
var defaultScale = new ObservablePoint(null, 1, 1);
var defaultOrigin = new ObservablePoint(null);
var UPDATE_COLOR = 1;
var UPDATE_BLEND = 2;
var UPDATE_VISIBLE = 4;
var UPDATE_TRANSFORM = 8;
var Container = class _Container extends eventemitter3_default {
  constructor(options = {}) {
    super();
    this.uid = uid("renderable");
    this._updateFlags = 15;
    this.renderGroup = null;
    this.parentRenderGroup = null;
    this.parentRenderGroupIndex = 0;
    this.didChange = false;
    this.didViewUpdate = false;
    this.relativeRenderGroupDepth = 0;
    this.children = [];
    this.parent = null;
    this.includeInBuild = true;
    this.measurable = true;
    this.isSimple = true;
    this.parentRenderLayer = null;
    this.updateTick = -1;
    this.localTransform = new Matrix();
    this.relativeGroupTransform = new Matrix();
    this.groupTransform = this.relativeGroupTransform;
    this.destroyed = false;
    this._position = new ObservablePoint(this, 0, 0);
    this._scale = defaultScale;
    this._pivot = defaultPivot;
    this._origin = defaultOrigin;
    this._skew = defaultSkew;
    this._cx = 1;
    this._sx = 0;
    this._cy = 0;
    this._sy = 1;
    this._rotation = 0;
    this.localColor = 16777215;
    this.localAlpha = 1;
    this.groupAlpha = 1;
    this.groupColor = 16777215;
    this.groupColorAlpha = 4294967295;
    this.localBlendMode = "inherit";
    this.groupBlendMode = "normal";
    this.localDisplayStatus = 7;
    this.globalDisplayStatus = 7;
    this._didContainerChangeTick = 0;
    this._didViewChangeTick = 0;
    this._didLocalTransformChangeId = -1;
    this.effects = [];
    assignWithIgnore(this, options, {
      children: true,
      parent: true,
      effects: true
    });
    options.children?.forEach((child) => this.addChild(child));
    options.parent?.addChild(this);
  }
  /**
   * Mixes all enumerable properties and methods from a source object to Container.
   * @param source - The source of properties and methods to mix in.
   * @deprecated since 8.8.0
   */
  static mixin(source) {
    deprecation("8.8.0", "Container.mixin is deprecated, please use extensions.mixin instead.");
    extensions.mixin(_Container, source);
  }
  // = 'default';
  /**
   * We now use the _didContainerChangeTick and _didViewChangeTick to track changes
   * @deprecated since 8.2.6
   * @ignore
   */
  set _didChangeId(value) {
    this._didViewChangeTick = value >> 12 & 4095;
    this._didContainerChangeTick = value & 4095;
  }
  /** @ignore */
  get _didChangeId() {
    return this._didContainerChangeTick & 4095 | (this._didViewChangeTick & 4095) << 12;
  }
  /**
   * Adds one or more children to the container.
   * The children will be rendered as part of this container's display list.
   * @example
   * ```ts
   * // Add a single child
   * container.addChild(sprite);
   *
   * // Add multiple children
   * container.addChild(background, player, foreground);
   *
   * // Add with type checking
   * const sprite = container.addChild<Sprite>(new Sprite(texture));
   * sprite.tint = 'red';
   * ```
   * @param children - The Container(s) to add to the container
   * @returns The first child that was added
   * @see {@link Container#removeChild} For removing children
   * @see {@link Container#addChildAt} For adding at specific index
   */
  addChild(...children) {
    if (!this.allowChildren) {
      deprecation(v8_0_0, "addChild: Only Containers will be allowed to add children in v8.0.0");
    }
    if (children.length > 1) {
      for (let i = 0; i < children.length; i++) {
        this.addChild(children[i]);
      }
      return children[0];
    }
    const child = children[0];
    const renderGroup = this.renderGroup || this.parentRenderGroup;
    if (child.parent === this) {
      this.children.splice(this.children.indexOf(child), 1);
      this.children.push(child);
      if (renderGroup) {
        renderGroup.structureDidChange = true;
      }
      return child;
    }
    if (child.parent) {
      child.parent.removeChild(child);
    }
    this.children.push(child);
    if (this.sortableChildren) this.sortDirty = true;
    child.parent = this;
    child.didChange = true;
    child._updateFlags = 15;
    if (renderGroup) {
      renderGroup.addChild(child);
    }
    this.emit("childAdded", child, this, this.children.length - 1);
    child.emit("added", this);
    this._didViewChangeTick++;
    if (child._zIndex !== 0) {
      child.depthOfChildModified();
    }
    return child;
  }
  /**
   * Removes one or more children from the container.
   * When removing multiple children, events will be triggered for each child in sequence.
   * @example
   * ```ts
   * // Remove a single child
   * const removed = container.removeChild(sprite);
   *
   * // Remove multiple children
   * const bg = container.removeChild(background, player, userInterface);
   *
   * // Remove with type checking
   * const sprite = container.removeChild<Sprite>(childSprite);
   * sprite.texture = newTexture;
   * ```
   * @param children - The Container(s) to remove
   * @returns The first child that was removed
   * @see {@link Container#addChild} For adding children
   * @see {@link Container#removeChildren} For removing multiple children
   */
  removeChild(...children) {
    if (children.length > 1) {
      for (let i = 0; i < children.length; i++) {
        this.removeChild(children[i]);
      }
      return children[0];
    }
    const child = children[0];
    const index = this.children.indexOf(child);
    if (index > -1) {
      this._didViewChangeTick++;
      this.children.splice(index, 1);
      if (this.renderGroup) {
        this.renderGroup.removeChild(child);
      } else if (this.parentRenderGroup) {
        this.parentRenderGroup.removeChild(child);
      }
      if (child.parentRenderLayer) {
        child.parentRenderLayer.detach(child);
      }
      child.parent = null;
      this.emit("childRemoved", child, this, index);
      child.emit("removed", this);
    }
    return child;
  }
  /** @ignore */
  _onUpdate(point) {
    if (point) {
      if (point === this._skew) {
        this._updateSkew();
      }
    }
    this._didContainerChangeTick++;
    if (this.didChange) return;
    this.didChange = true;
    if (this.parentRenderGroup) {
      this.parentRenderGroup.onChildUpdate(this);
    }
  }
  set isRenderGroup(value) {
    if (!!this.renderGroup === value) return;
    if (value) {
      this.enableRenderGroup();
    } else {
      this.disableRenderGroup();
    }
  }
  /**
   * Returns true if this container is a render group.
   * This means that it will be rendered as a separate pass, with its own set of instructions
   * @advanced
   */
  get isRenderGroup() {
    return !!this.renderGroup;
  }
  /**
   * Calling this enables a render group for this container.
   * This means it will be rendered as a separate set of instructions.
   * The transform of the container will also be handled on the GPU rather than the CPU.
   * @advanced
   */
  enableRenderGroup() {
    if (this.renderGroup) return;
    const parentRenderGroup = this.parentRenderGroup;
    parentRenderGroup?.removeChild(this);
    this.renderGroup = BigPool.get(RenderGroup, this);
    this.groupTransform = Matrix.IDENTITY;
    parentRenderGroup?.addChild(this);
    this._updateIsSimple();
  }
  /**
   * This will disable the render group for this container.
   * @advanced
   */
  disableRenderGroup() {
    if (!this.renderGroup) return;
    const parentRenderGroup = this.parentRenderGroup;
    parentRenderGroup?.removeChild(this);
    BigPool.return(this.renderGroup);
    this.renderGroup = null;
    this.groupTransform = this.relativeGroupTransform;
    parentRenderGroup?.addChild(this);
    this._updateIsSimple();
  }
  /** @ignore */
  _updateIsSimple() {
    this.isSimple = !this.renderGroup && this.effects.length === 0;
  }
  /**
   * Current transform of the object based on world (parent) factors.
   *
   * This matrix represents the absolute transformation in the scene graph.
   * @example
   * ```ts
   * // Get world position
   * const worldPos = container.worldTransform;
   * console.log(`World position: (${worldPos.tx}, ${worldPos.ty})`);
   * ```
   * @readonly
   * @see {@link Container#localTransform} For local space transform
   */
  get worldTransform() {
    this._worldTransform || (this._worldTransform = new Matrix());
    if (this.renderGroup) {
      this._worldTransform.copyFrom(this.renderGroup.worldTransform);
    } else if (this.parentRenderGroup) {
      this._worldTransform.appendFrom(this.relativeGroupTransform, this.parentRenderGroup.worldTransform);
    }
    return this._worldTransform;
  }
  /**
   * The position of the container on the x axis relative to the local coordinates of the parent.
   *
   * An alias to position.x
   * @example
   * ```ts
   * // Basic position
   * container.x = 100;
   * ```
   */
  get x() {
    return this._position.x;
  }
  set x(value) {
    this._position.x = value;
  }
  /**
   * The position of the container on the y axis relative to the local coordinates of the parent.
   *
   * An alias to position.y
   * @example
   * ```ts
   * // Basic position
   * container.y = 200;
   * ```
   */
  get y() {
    return this._position.y;
  }
  set y(value) {
    this._position.y = value;
  }
  /**
   * The coordinate of the object relative to the local coordinates of the parent.
   * @example
   * ```ts
   * // Basic position setting
   * container.position.set(100, 200);
   * container.position.set(100); // Sets both x and y to 100
   * // Using point data
   * container.position = { x: 50, y: 75 };
   * ```
   * @since 4.0.0
   */
  get position() {
    return this._position;
  }
  set position(value) {
    this._position.copyFrom(value);
  }
  /**
   * The rotation of the object in radians.
   *
   * > [!NOTE] 'rotation' and 'angle' have the same effect on a display object;
   * > rotation is in radians, angle is in degrees.
   * @example
   * ```ts
   * // Basic rotation
   * container.rotation = Math.PI / 4; // 45 degrees
   *
   * // Convert from degrees
   * const degrees = 45;
   * container.rotation = degrees * Math.PI / 180;
   *
   * // Rotate around center
   * container.pivot.set(container.width / 2, container.height / 2);
   * container.rotation = Math.PI; // 180 degrees
   *
   * // Rotate around center with origin
   * container.origin.set(container.width / 2, container.height / 2);
   * container.rotation = Math.PI; // 180 degrees
   * ```
   */
  get rotation() {
    return this._rotation;
  }
  set rotation(value) {
    if (this._rotation !== value) {
      this._rotation = value;
      this._onUpdate(this._skew);
    }
  }
  /**
   * The angle of the object in degrees.
   *
   * > [!NOTE] 'rotation' and 'angle' have the same effect on a display object;
   * > rotation is in radians, angle is in degrees.
   * @example
   * ```ts
   * // Basic angle rotation
   * sprite.angle = 45; // 45 degrees
   *
   * // Rotate around center
   * sprite.pivot.set(sprite.width / 2, sprite.height / 2);
   * sprite.angle = 180; // Half rotation
   *
   * // Rotate around center with origin
   * sprite.origin.set(sprite.width / 2, sprite.height / 2);
   * sprite.angle = 180; // Half rotation
   *
   * // Reset rotation
   * sprite.angle = 0;
   * ```
   */
  get angle() {
    return this.rotation * RAD_TO_DEG;
  }
  set angle(value) {
    this.rotation = value * DEG_TO_RAD;
  }
  /**
   * The center of rotation, scaling, and skewing for this display object in its local space.
   * The `position` is the projection of `pivot` in the parent's local space.
   *
   * By default, the pivot is the origin (0, 0).
   * @example
   * ```ts
   * // Rotate around center
   * container.pivot.set(container.width / 2, container.height / 2);
   * container.rotation = Math.PI; // Rotates around center
   * ```
   * @since 4.0.0
   */
  get pivot() {
    if (this._pivot === defaultPivot) {
      this._pivot = new ObservablePoint(this, 0, 0);
    }
    return this._pivot;
  }
  set pivot(value) {
    if (this._pivot === defaultPivot) {
      this._pivot = new ObservablePoint(this, 0, 0);
      if (this._origin !== defaultOrigin) {
        warn(`Setting both a pivot and origin on a Container is not recommended. This can lead to unexpected behavior if not handled carefully.`);
      }
    }
    typeof value === "number" ? this._pivot.set(value) : this._pivot.copyFrom(value);
  }
  /**
   * The skew factor for the object in radians. Skewing is a transformation that distorts
   * the object by rotating it differently at each point, creating a non-uniform shape.
   * @example
   * ```ts
   * // Basic skewing
   * container.skew.set(0.5, 0); // Skew horizontally
   * container.skew.set(0, 0.5); // Skew vertically
   *
   * // Skew with point data
   * container.skew = { x: 0.3, y: 0.3 }; // Diagonal skew
   *
   * // Reset skew
   * container.skew.set(0, 0);
   *
   * // Animate skew
   * app.ticker.add(() => {
   *     // Create wave effect
   *     container.skew.x = Math.sin(Date.now() / 1000) * 0.3;
   * });
   *
   * // Combine with rotation
   * container.rotation = Math.PI / 4; // 45 degrees
   * container.skew.set(0.2, 0.2); // Skew the rotated object
   * ```
   * @since 4.0.0
   * @type {ObservablePoint} Point-like object with x/y properties in radians
   * @default {x: 0, y: 0}
   */
  get skew() {
    if (this._skew === defaultSkew) {
      this._skew = new ObservablePoint(this, 0, 0);
    }
    return this._skew;
  }
  set skew(value) {
    if (this._skew === defaultSkew) {
      this._skew = new ObservablePoint(this, 0, 0);
    }
    this._skew.copyFrom(value);
  }
  /**
   * The scale factors of this object along the local coordinate axes.
   *
   * The default scale is (1, 1).
   * @example
   * ```ts
   * // Basic scaling
   * container.scale.set(2, 2); // Scales to double size
   * container.scale.set(2); // Scales uniformly to double size
   * container.scale = 2; // Scales uniformly to double size
   * // Scale to a specific width and height
   * container.setSize(200, 100); // Sets width to 200 and height to 100
   * ```
   * @since 4.0.0
   */
  get scale() {
    if (this._scale === defaultScale) {
      this._scale = new ObservablePoint(this, 1, 1);
    }
    return this._scale;
  }
  set scale(value) {
    if (this._scale === defaultScale) {
      this._scale = new ObservablePoint(this, 0, 0);
    }
    if (typeof value === "string") {
      value = parseFloat(value);
    }
    typeof value === "number" ? this._scale.set(value) : this._scale.copyFrom(value);
  }
  /**
   * @experimental
   * The origin point around which the container rotates and scales without affecting its position.
   * Unlike pivot, changing the origin will not move the container's position.
   * @example
   * ```ts
   * // Rotate around center point
   * container.origin.set(container.width / 2, container.height / 2);
   * container.rotation = Math.PI; // Rotates around center
   *
   * // Reset origin
   * container.origin.set(0, 0);
   * ```
   */
  get origin() {
    if (this._origin === defaultOrigin) {
      this._origin = new ObservablePoint(this, 0, 0);
    }
    return this._origin;
  }
  set origin(value) {
    if (this._origin === defaultOrigin) {
      this._origin = new ObservablePoint(this, 0, 0);
      if (this._pivot !== defaultPivot) {
        warn(`Setting both a pivot and origin on a Container is not recommended. This can lead to unexpected behavior if not handled carefully.`);
      }
    }
    typeof value === "number" ? this._origin.set(value) : this._origin.copyFrom(value);
  }
  /**
   * The width of the Container, setting this will actually modify the scale to achieve the value set.
   * > [!NOTE] Changing the width will adjust the scale.x property of the container while maintaining its aspect ratio.
   * > [!NOTE] If you want to set both width and height at the same time, use {@link Container#setSize}
   * as it is more optimized by not recalculating the local bounds twice.
   * @example
   * ```ts
   * // Basic width setting
   * container.width = 100;
   * // Optimized width setting
   * container.setSize(100, 100);
   * ```
   */
  get width() {
    return Math.abs(this.scale.x * this.getLocalBounds().width);
  }
  set width(value) {
    const localWidth = this.getLocalBounds().width;
    this._setWidth(value, localWidth);
  }
  /**
   * The height of the Container,
   * > [!NOTE] Changing the height will adjust the scale.y property of the container while maintaining its aspect ratio.
   * > [!NOTE] If you want to set both width and height at the same time, use {@link Container#setSize}
   * as it is more optimized by not recalculating the local bounds twice.
   * @example
   * ```ts
   * // Basic height setting
   * container.height = 200;
   * // Optimized height setting
   * container.setSize(100, 200);
   * ```
   */
  get height() {
    return Math.abs(this.scale.y * this.getLocalBounds().height);
  }
  set height(value) {
    const localHeight = this.getLocalBounds().height;
    this._setHeight(value, localHeight);
  }
  /**
   * Retrieves the size of the container as a [Size]{@link Size} object.
   *
   * This is faster than get the width and height separately.
   * @example
   * ```ts
   * // Basic size retrieval
   * const size = container.getSize();
   * console.log(`Size: ${size.width}x${size.height}`);
   *
   * // Reuse existing size object
   * const reuseSize = { width: 0, height: 0 };
   * container.getSize(reuseSize);
   * ```
   * @param out - Optional object to store the size in.
   * @returns The size of the container.
   */
  getSize(out) {
    if (!out) {
      out = {};
    }
    const bounds = this.getLocalBounds();
    out.width = Math.abs(this.scale.x * bounds.width);
    out.height = Math.abs(this.scale.y * bounds.height);
    return out;
  }
  /**
   * Sets the size of the container to the specified width and height.
   * This is more efficient than setting width and height separately as it only recalculates bounds once.
   * @example
   * ```ts
   * // Basic size setting
   * container.setSize(100, 200);
   *
   * // Set uniform size
   * container.setSize(100); // Sets both width and height to 100
   * ```
   * @param value - This can be either a number or a [Size]{@link Size} object.
   * @param height - The height to set. Defaults to the value of `width` if not provided.
   */
  setSize(value, height) {
    const size = this.getLocalBounds();
    if (typeof value === "object") {
      height = value.height ?? value.width;
      value = value.width;
    } else {
      height ?? (height = value);
    }
    value !== void 0 && this._setWidth(value, size.width);
    height !== void 0 && this._setHeight(height, size.height);
  }
  /** Called when the skew or the rotation changes. */
  _updateSkew() {
    const rotation = this._rotation;
    const skew = this._skew;
    this._cx = Math.cos(rotation + skew._y);
    this._sx = Math.sin(rotation + skew._y);
    this._cy = -Math.sin(rotation - skew._x);
    this._sy = Math.cos(rotation - skew._x);
  }
  /**
   * Updates the transform properties of the container.
   * Allows partial updates of transform properties for optimized manipulation.
   * @example
   * ```ts
   * // Basic transform update
   * container.updateTransform({
   *     x: 100,
   *     y: 200,
   *     rotation: Math.PI / 4
   * });
   *
   * // Scale and rotate around center
   * sprite.updateTransform({
   *     pivotX: sprite.width / 2,
   *     pivotY: sprite.height / 2,
   *     scaleX: 2,
   *     scaleY: 2,
   *     rotation: Math.PI
   * });
   *
   * // Update position only
   * button.updateTransform({
   *     x: button.x + 10, // Move right
   *     y: button.y      // Keep same y
   * });
   * ```
   * @param opts - Transform options to update
   * @param opts.x - The x position
   * @param opts.y - The y position
   * @param opts.scaleX - The x-axis scale factor
   * @param opts.scaleY - The y-axis scale factor
   * @param opts.rotation - The rotation in radians
   * @param opts.skewX - The x-axis skew factor
   * @param opts.skewY - The y-axis skew factor
   * @param opts.pivotX - The x-axis pivot point
   * @param opts.pivotY - The y-axis pivot point
   * @returns This container, for chaining
   * @see {@link Container#setFromMatrix} For matrix-based transforms
   * @see {@link Container#position} For direct position access
   */
  updateTransform(opts) {
    this.position.set(
      typeof opts.x === "number" ? opts.x : this.position.x,
      typeof opts.y === "number" ? opts.y : this.position.y
    );
    this.scale.set(
      typeof opts.scaleX === "number" ? opts.scaleX : this.scale.x,
      typeof opts.scaleY === "number" ? opts.scaleY : this.scale.y
    );
    this.rotation = typeof opts.rotation === "number" ? opts.rotation : this.rotation;
    this.skew.set(
      typeof opts.skewX === "number" ? opts.skewX : this.skew.x,
      typeof opts.skewY === "number" ? opts.skewY : this.skew.y
    );
    this.pivot.set(
      typeof opts.pivotX === "number" ? opts.pivotX : this.pivot.x,
      typeof opts.pivotY === "number" ? opts.pivotY : this.pivot.y
    );
    this.origin.set(
      typeof opts.originX === "number" ? opts.originX : this.origin.x,
      typeof opts.originY === "number" ? opts.originY : this.origin.y
    );
    return this;
  }
  /**
   * Updates the local transform properties by decomposing the given matrix.
   * Extracts position, scale, rotation, and skew from a transformation matrix.
   * @example
   * ```ts
   * // Basic matrix transform
   * const matrix = new Matrix()
   *     .translate(100, 100)
   *     .rotate(Math.PI / 4)
   *     .scale(2, 2);
   *
   * container.setFromMatrix(matrix);
   *
   * // Copy transform from another container
   * const source = new Container();
   * source.position.set(100, 100);
   * source.rotation = Math.PI / 2;
   *
   * target.setFromMatrix(source.localTransform);
   *
   * // Reset transform
   * container.setFromMatrix(Matrix.IDENTITY);
   * ```
   * @param matrix - The matrix to use for updating the transform
   * @see {@link Container#updateTransform} For property-based updates
   * @see {@link Matrix#decompose} For matrix decomposition details
   */
  setFromMatrix(matrix) {
    matrix.decompose(this);
  }
  /** Updates the local transform. */
  updateLocalTransform() {
    const localTransformChangeId = this._didContainerChangeTick;
    if (this._didLocalTransformChangeId === localTransformChangeId) return;
    this._didLocalTransformChangeId = localTransformChangeId;
    const lt = this.localTransform;
    const scale = this._scale;
    const pivot = this._pivot;
    const origin = this._origin;
    const position = this._position;
    const sx = scale._x;
    const sy = scale._y;
    const px = pivot._x;
    const py = pivot._y;
    const ox = -origin._x;
    const oy = -origin._y;
    lt.a = this._cx * sx;
    lt.b = this._sx * sx;
    lt.c = this._cy * sy;
    lt.d = this._sy * sy;
    lt.tx = position._x - (px * lt.a + py * lt.c) + (ox * lt.a + oy * lt.c) - ox;
    lt.ty = position._y - (px * lt.b + py * lt.d) + (ox * lt.b + oy * lt.d) - oy;
  }
  // / ///// color related stuff
  set alpha(value) {
    if (value === this.localAlpha) return;
    this.localAlpha = value;
    this._updateFlags |= UPDATE_COLOR;
    this._onUpdate();
  }
  /**
   * The opacity of the object relative to its parent's opacity.
   * Value ranges from 0 (fully transparent) to 1 (fully opaque).
   * @example
   * ```ts
   * // Basic transparency
   * sprite.alpha = 0.5; // 50% opacity
   *
   * // Inherited opacity
   * container.alpha = 0.5;
   * const child = new Sprite(texture);
   * child.alpha = 0.5;
   * container.addChild(child);
   * // child's effective opacity is 0.25 (0.5 * 0.5)
   * ```
   * @default 1
   * @see {@link Container#visible} For toggling visibility
   * @see {@link Container#renderable} For render control
   */
  get alpha() {
    return this.localAlpha;
  }
  set tint(value) {
    const tempColor = Color.shared.setValue(value ?? 16777215);
    const bgr = tempColor.toBgrNumber();
    if (bgr === this.localColor) return;
    this.localColor = bgr;
    this._updateFlags |= UPDATE_COLOR;
    this._onUpdate();
  }
  /**
   * The tint applied to the sprite.
   *
   * This can be any valid {@link ColorSource}.
   * @example
   * ```ts
   * // Basic color tinting
   * container.tint = 0xff0000; // Red tint
   * container.tint = 'red';    // Same as above
   * container.tint = '#00ff00'; // Green
   * container.tint = 'rgb(0,0,255)'; // Blue
   *
   * // Remove tint
   * container.tint = 0xffffff; // White = no tint
   * container.tint = null;     // Also removes tint
   * ```
   * @default 0xFFFFFF
   * @see {@link Container#alpha} For transparency
   * @see {@link Container#visible} For visibility control
   */
  get tint() {
    return bgr2rgb(this.localColor);
  }
  // / //////////////// blend related stuff
  set blendMode(value) {
    if (this.localBlendMode === value) return;
    if (this.parentRenderGroup) {
      this.parentRenderGroup.structureDidChange = true;
    }
    this._updateFlags |= UPDATE_BLEND;
    this.localBlendMode = value;
    this._onUpdate();
  }
  /**
   * The blend mode to be applied to the sprite. Controls how pixels are blended when rendering.
   *
   * Setting to 'normal' will reset to default blending.
   * > [!NOTE] More blend modes are available after importing the `pixi.js/advanced-blend-modes` sub-export.
   * @example
   * ```ts
   * // Basic blend modes
   * sprite.blendMode = 'add';        // Additive blending
   * sprite.blendMode = 'multiply';   // Multiply colors
   * sprite.blendMode = 'screen';     // Screen blend
   *
   * // Reset blend mode
   * sprite.blendMode = 'normal';     // Normal blending
   * ```
   * @default 'normal'
   * @see {@link Container#alpha} For transparency
   * @see {@link Container#tint} For color adjustments
   */
  get blendMode() {
    return this.localBlendMode;
  }
  // / ///////// VISIBILITY / RENDERABLE /////////////////
  /**
   * The visibility of the object. If false the object will not be drawn,
   * and the transform will not be updated.
   * @example
   * ```ts
   * // Basic visibility toggle
   * sprite.visible = false; // Hide sprite
   * sprite.visible = true;  // Show sprite
   * ```
   * @default true
   * @see {@link Container#renderable} For render-only control
   * @see {@link Container#alpha} For transparency
   */
  get visible() {
    return !!(this.localDisplayStatus & 2);
  }
  set visible(value) {
    const valueNumber = value ? 2 : 0;
    if ((this.localDisplayStatus & 2) === valueNumber) return;
    if (this.parentRenderGroup) {
      this.parentRenderGroup.structureDidChange = true;
    }
    this._updateFlags |= UPDATE_VISIBLE;
    this.localDisplayStatus ^= 2;
    this._onUpdate();
    this.emit("visibleChanged", value);
  }
  /** @ignore */
  get culled() {
    return !(this.localDisplayStatus & 4);
  }
  /** @ignore */
  set culled(value) {
    const valueNumber = value ? 0 : 4;
    if ((this.localDisplayStatus & 4) === valueNumber) return;
    if (this.parentRenderGroup) {
      this.parentRenderGroup.structureDidChange = true;
    }
    this._updateFlags |= UPDATE_VISIBLE;
    this.localDisplayStatus ^= 4;
    this._onUpdate();
  }
  /**
   * Controls whether this object can be rendered. If false the object will not be drawn,
   * but the transform will still be updated. This is different from visible, which skips
   * transform updates.
   * @example
   * ```ts
   * // Basic render control
   * sprite.renderable = false; // Skip rendering
   * sprite.renderable = true;  // Enable rendering
   * ```
   * @default true
   * @see {@link Container#visible} For skipping transform updates
   * @see {@link Container#alpha} For transparency
   */
  get renderable() {
    return !!(this.localDisplayStatus & 1);
  }
  set renderable(value) {
    const valueNumber = value ? 1 : 0;
    if ((this.localDisplayStatus & 1) === valueNumber) return;
    this._updateFlags |= UPDATE_VISIBLE;
    this.localDisplayStatus ^= 1;
    if (this.parentRenderGroup) {
      this.parentRenderGroup.structureDidChange = true;
    }
    this._onUpdate();
  }
  /**
   * Whether or not the object should be rendered.
   * @advanced
   */
  get isRenderable() {
    return this.localDisplayStatus === 7 && this.groupAlpha > 0;
  }
  /**
   * Removes all internal references and listeners as well as removes children from the display list.
   * Do not use a Container after calling `destroy`.
   * @param options - Options parameter. A boolean will act as if all options
   *  have been set to that value
   * @example
   * ```ts
   * container.destroy();
   * container.destroy(true);
   * container.destroy({ children: true });
   * container.destroy({ children: true, texture: true, textureSource: true });
   * ```
   */
  destroy(options = false) {
    if (this.destroyed) return;
    this.destroyed = true;
    let oldChildren;
    if (this.children.length) {
      oldChildren = this.removeChildren(0, this.children.length);
    }
    this.removeFromParent();
    this.parent = null;
    this._maskEffect = null;
    this._filterEffect = null;
    this.effects = null;
    this._position = null;
    this._scale = null;
    this._pivot = null;
    this._origin = null;
    this._skew = null;
    this.emit("destroyed", this);
    this.removeAllListeners();
    const destroyChildren = typeof options === "boolean" ? options : options?.children;
    if (destroyChildren && oldChildren) {
      for (let i = 0; i < oldChildren.length; ++i) {
        oldChildren[i].destroy(options);
      }
    }
    this.renderGroup?.destroy();
    this.renderGroup = null;
  }
};
extensions.mixin(
  Container,
  childrenHelperMixin,
  getFastGlobalBoundsMixin,
  toLocalGlobalMixin,
  onRenderMixin,
  measureMixin,
  effectsMixin,
  findMixin,
  sortMixin,
  cullingMixin,
  cacheAsTextureMixin,
  getGlobalMixin,
  collectRenderablesMixin
);

export {
  cullingMixin,
  ObservablePoint,
  cacheAsTextureMixin,
  removeItems,
  childrenHelperMixin,
  collectRenderablesMixin,
  FilterEffect,
  MaskEffectManagerClass,
  MaskEffectManager,
  effectsMixin,
  findMixin,
  matrixPool,
  boundsPool,
  getFastGlobalBoundsMixin,
  getGlobalBounds,
  updateTransformBackwards,
  multiplyColors,
  bgr2rgb,
  getGlobalMixin,
  getLocalBounds,
  checkChildrenDidChange,
  measureMixin,
  onRenderMixin,
  sortMixin,
  toLocalGlobalMixin,
  TexturePoolClass,
  TexturePool,
  RenderGroup,
  assignWithIgnore,
  UPDATE_COLOR,
  UPDATE_BLEND,
  UPDATE_VISIBLE,
  UPDATE_TRANSFORM,
  Container
};
