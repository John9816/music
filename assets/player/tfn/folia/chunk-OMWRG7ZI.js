// Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; adapted for TuneFreeNext. See THIRD_PARTY_NOTICES.md and scripts/vendor_folia_skins.mjs.
import {
  Container
} from "./chunk-RMIIME3Z.js";
import {
  Color,
  ExtensionType,
  GlobalResourceRegistry,
  deprecation,
  eventemitter3_default,
  extensions,
  uid,
  v8_0_0
} from "./chunk-NJ7XHR5M.js";

// scripts/folia/node_modules/pixi.js/lib/utils/browser/unsafeEvalSupported.mjs
var unsafeEval;
function unsafeEvalSupported() {
  if (typeof unsafeEval === "boolean") {
    return unsafeEval;
  }
  try {
    const func = new Function("param1", "param2", "param3", "return param1[param2] === param3;");
    unsafeEval = func({ a: "b" }, "a", "b") === true;
  } catch (_e) {
    unsafeEval = false;
  }
  return unsafeEval;
}

// scripts/folia/node_modules/pixi.js/lib/environment/autoDetectEnvironment.mjs
var environments = [];
extensions.handleByNamedList(ExtensionType.Environment, environments);
async function loadEnvironmentExtensions(skip) {
  if (skip) return;
  for (let i = 0; i < environments.length; i++) {
    const env = environments[i];
    if (env.value.test()) {
      await env.value.load();
      return;
    }
  }
}
async function autoDetectEnvironment(add) {
  return loadEnvironmentExtensions(!add);
}

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/gl/const.mjs
var CLEAR = /* @__PURE__ */ ((CLEAR2) => {
  CLEAR2[CLEAR2["NONE"] = 0] = "NONE";
  CLEAR2[CLEAR2["COLOR"] = 16384] = "COLOR";
  CLEAR2[CLEAR2["STENCIL"] = 1024] = "STENCIL";
  CLEAR2[CLEAR2["DEPTH"] = 256] = "DEPTH";
  CLEAR2[CLEAR2["COLOR_DEPTH"] = 16640] = "COLOR_DEPTH";
  CLEAR2[CLEAR2["COLOR_STENCIL"] = 17408] = "COLOR_STENCIL";
  CLEAR2[CLEAR2["DEPTH_STENCIL"] = 1280] = "DEPTH_STENCIL";
  CLEAR2[CLEAR2["ALL"] = 17664] = "ALL";
  return CLEAR2;
})(CLEAR || {});

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/shared/system/SystemRunner.mjs
var SystemRunner = class {
  /**
   * @param name - The function name that will be executed on the listeners added to this Runner.
   */
  constructor(name) {
    this.items = [];
    this._name = name;
  }
  /* jsdoc/check-param-names */
  /**
   * Dispatch/Broadcast Runner to all listeners added to the queue.
   * @param {...any} params - (optional) parameters to pass to each listener
   */
  /* jsdoc/check-param-names */
  emit(a0, a1, a2, a3, a4, a5, a6, a7) {
    const { name, items } = this;
    for (let i = 0, len = items.length; i < len; i++) {
      items[i][name](a0, a1, a2, a3, a4, a5, a6, a7);
    }
    return this;
  }
  /**
   * Add a listener to the Runner
   *
   * Runners do not need to have scope or functions passed to them.
   * All that is required is to pass the listening object and ensure that it has contains a function that has the same name
   * as the name provided to the Runner when it was created.
   *
   * Eg A listener passed to this Runner will require a 'complete' function.
   *
   * ```ts
   * import { Runner } from 'pixi.js';
   *
   * const complete = new Runner('complete');
   * ```
   *
   * The scope used will be the object itself.
   * @param {any} item - The object that will be listening.
   */
  add(item) {
    if (item[this._name]) {
      this.remove(item);
      this.items.push(item);
    }
    return this;
  }
  /**
   * Remove a single listener from the dispatch queue.
   * @param {any} item - The listener that you would like to remove.
   */
  remove(item) {
    const index = this.items.indexOf(item);
    if (index !== -1) {
      this.items.splice(index, 1);
    }
    return this;
  }
  /**
   * Check to see if the listener is already in the Runner
   * @param {any} item - The listener that you would like to check.
   */
  contains(item) {
    return this.items.indexOf(item) !== -1;
  }
  /** Remove all listeners from the Runner */
  removeAll() {
    this.items.length = 0;
    return this;
  }
  /** Remove all references, don't use after this. */
  destroy() {
    this.removeAll();
    this.items = null;
    this._name = null;
  }
  /**
   * `true` if there are no this Runner contains no listeners
   * @readonly
   */
  get empty() {
    return this.items.length === 0;
  }
  /**
   * The name of the runner.
   * @readonly
   */
  get name() {
    return this._name;
  }
};

// scripts/folia/node_modules/pixi.js/lib/rendering/renderers/shared/system/AbstractRenderer.mjs
var defaultRunners = [
  "init",
  "destroy",
  "contextChange",
  "resolutionChange",
  "resetState",
  "renderEnd",
  "renderStart",
  "render",
  "update",
  "postrender",
  "prerender"
];
var _AbstractRenderer = class _AbstractRenderer2 extends eventemitter3_default {
  /**
   * Set up a system with a collection of SystemClasses and runners.
   * Systems are attached dynamically to this class when added.
   * @param config - the config for the system manager
   */
  constructor(config) {
    super();
    this.tick = 0;
    this.uid = uid("renderer");
    this.runners = /* @__PURE__ */ Object.create(null);
    this.renderPipes = /* @__PURE__ */ Object.create(null);
    this._initOptions = {};
    this._systemsHash = /* @__PURE__ */ Object.create(null);
    this.type = config.type;
    this.name = config.name;
    this.config = config;
    const combinedRunners = [...defaultRunners, ...this.config.runners ?? []];
    this._addRunners(...combinedRunners);
    this._unsafeEvalCheck();
  }
  /**
   * Initialize the renderer.
   * @param options - The options to use to create the renderer.
   */
  async init(options = {}) {
    const skip = options.skipExtensionImports === true ? true : options.manageImports === false;
    await loadEnvironmentExtensions(skip);
    if (!skip && this.config.loaders) {
      await Promise.all(this.config.loaders.map((loader) => loader.value.load()));
    }
    this._addSystems(this.config.systems);
    this._addPipes(this.config.renderPipes, this.config.renderPipeAdaptors);
    for (const systemName in this._systemsHash) {
      const system = this._systemsHash[systemName];
      const defaultSystemOptions = system.constructor.defaultOptions;
      options = { ...defaultSystemOptions, ...options };
    }
    options = { ..._AbstractRenderer2.defaultOptions, ...options };
    this._roundPixels = options.roundPixels ? 1 : 0;
    for (let i = 0; i < this.runners.init.items.length; i++) {
      await this.runners.init.items[i].init(options);
    }
    this._initOptions = options;
  }
  render(args, deprecated) {
    this.tick++;
    let options = args;
    if (options instanceof Container) {
      options = { container: options };
      if (deprecated) {
        deprecation(v8_0_0, "passing a second argument is deprecated, please use render options instead");
        options.target = deprecated.renderTexture;
      }
    }
    options.target || (options.target = this.view.renderTarget);
    if (options.target === this.view.renderTarget) {
      this._lastObjectRendered = options.container;
      options.clearColor ?? (options.clearColor = this.background.colorRgba);
      options.clear ?? (options.clear = this.background.clearBeforeRender);
    }
    if (options.clearColor) {
      const isRGBAArray = Array.isArray(options.clearColor) && options.clearColor.length === 4;
      options.clearColor = isRGBAArray ? options.clearColor : Color.shared.setValue(options.clearColor).toArray();
    }
    if (!options.transform) {
      options.container.updateLocalTransform();
      options.transform = options.container.localTransform;
    }
    if (!options.container.visible) {
      return;
    }
    options.container.enableRenderGroup();
    this.runners.prerender.emit(options);
    this.runners.renderStart.emit(options);
    this.runners.render.emit(options);
    this.runners.renderEnd.emit(options);
    this.runners.postrender.emit(options);
  }
  /**
   * Resizes the WebGL view to the specified width and height.
   * @param desiredScreenWidth - The desired width of the screen.
   * @param desiredScreenHeight - The desired height of the screen.
   * @param resolution - The resolution / device pixel ratio of the renderer.
   */
  resize(desiredScreenWidth, desiredScreenHeight, resolution) {
    const previousResolution = this.view.resolution;
    this.view.resize(desiredScreenWidth, desiredScreenHeight, resolution);
    this.emit("resize", this.view.screen.width, this.view.screen.height, this.view.resolution);
    if (resolution !== void 0 && resolution !== previousResolution) {
      this.runners.resolutionChange.emit(resolution);
    }
  }
  /**
   * Clears the render target.
   * @param options - The options to use when clearing the render target.
   * @param options.target - The render target to clear.
   * @param options.clearColor - The color to clear with.
   * @param options.clear - The clear mode to use.
   * @advanced
   */
  clear(options = {}) {
    const renderer = this;
    options.target || (options.target = renderer.renderTarget.renderTarget);
    options.clearColor || (options.clearColor = this.background.colorRgba);
    options.clear ?? (options.clear = CLEAR.ALL);
    const { clear, clearColor, target, mipLevel, layer } = options;
    Color.shared.setValue(clearColor ?? this.background.colorRgba);
    renderer.renderTarget.clear(target, clear, Color.shared.toArray(), mipLevel ?? 0, layer ?? 0);
  }
  /** The resolution / device pixel ratio of the renderer. */
  get resolution() {
    return this.view.resolution;
  }
  set resolution(value) {
    this.view.resolution = value;
    this.runners.resolutionChange.emit(value);
  }
  /**
   * Same as view.width, actual number of pixels in the canvas by horizontal.
   * @type {number}
   * @readonly
   * @default 800
   */
  get width() {
    return this.view.texture.frame.width;
  }
  /**
   * Same as view.height, actual number of pixels in the canvas by vertical.
   * @default 600
   */
  get height() {
    return this.view.texture.frame.height;
  }
  // NOTE: this was `view` in v7
  /**
   * The canvas element that everything is drawn to.
   * @type {environment.ICanvas}
   */
  get canvas() {
    return this.view.canvas;
  }
  /**
   * the last object rendered by the renderer. Useful for other plugins like interaction managers
   * @readonly
   */
  get lastObjectRendered() {
    return this._lastObjectRendered;
  }
  /**
   * Flag if we are rendering to the screen vs renderTexture
   * @readonly
   * @default true
   */
  get renderingToScreen() {
    const renderer = this;
    return renderer.renderTarget.renderingToScreen;
  }
  /**
   * Measurements of the screen. (0, 0, screenWidth, screenHeight).
   *
   * Its safe to use as filterArea or hitArea for the whole stage.
   */
  get screen() {
    return this.view.screen;
  }
  /**
   * Create a bunch of runners based of a collection of ids
   * @param runnerIds - the runner ids to add
   */
  _addRunners(...runnerIds) {
    runnerIds.forEach((runnerId) => {
      this.runners[runnerId] = new SystemRunner(runnerId);
    });
  }
  _addSystems(systems) {
    let i;
    for (i in systems) {
      const val = systems[i];
      this._addSystem(val.value, val.name);
    }
  }
  /**
   * Add a new system to the renderer.
   * @param ClassRef - Class reference
   * @param name - Property name for system, if not specified
   *        will use a static `name` property on the class itself. This
   *        name will be assigned as s property on the Renderer so make
   *        sure it doesn't collide with properties on Renderer.
   * @returns Return instance of renderer
   */
  _addSystem(ClassRef, name) {
    const system = new ClassRef(this);
    if (this[name]) {
      throw new Error(`Whoops! The name "${name}" is already in use`);
    }
    this[name] = system;
    this._systemsHash[name] = system;
    for (const i in this.runners) {
      this.runners[i].add(system);
    }
    return this;
  }
  _addPipes(pipes, pipeAdaptors) {
    const adaptors = pipeAdaptors.reduce((acc, adaptor) => {
      acc[adaptor.name] = adaptor.value;
      return acc;
    }, {});
    pipes.forEach((pipe) => {
      const PipeClass = pipe.value;
      const name = pipe.name;
      const Adaptor = adaptors[name];
      this.renderPipes[name] = new PipeClass(
        this,
        Adaptor ? new Adaptor() : null
      );
      this.runners.destroy.add(this.renderPipes[name]);
    });
  }
  destroy(options = false) {
    this.runners.destroy.items.reverse();
    this.runners.destroy.emit(options);
    if (options === true || typeof options === "object" && options.releaseGlobalResources) {
      GlobalResourceRegistry.release();
    }
    Object.values(this.runners).forEach((runner) => {
      runner.destroy();
    });
    this._systemsHash = null;
    this.renderPipes = null;
    this.removeAllListeners();
  }
  /**
   * Generate a texture from a container.
   * @param options - options or container target to use when generating the texture
   * @returns a texture
   */
  generateTexture(options) {
    return this.textureGenerator.generateTexture(options);
  }
  /**
   * Whether the renderer will round coordinates to whole pixels when rendering.
   * Can be overridden on a per scene item basis.
   */
  get roundPixels() {
    return !!this._roundPixels;
  }
  /**
   * Overridable function by `pixi.js/unsafe-eval` to silence
   * throwing an error if platform doesn't support unsafe-evals.
   * @private
   * @ignore
   */
  _unsafeEvalCheck() {
    if (!unsafeEvalSupported()) {
      throw new Error("Current environment does not allow unsafe-eval, please use pixi.js/unsafe-eval module to enable support.");
    }
  }
  /**
   * Resets the rendering state of the renderer.
   * This is useful when you want to use the WebGL context directly and need to ensure PixiJS's internal state
   * stays synchronized. When modifying the WebGL context state externally, calling this method before the next Pixi
   * render will reset all internal caches and ensure it executes correctly.
   *
   * This is particularly useful when combining PixiJS with other rendering engines like Three.js:
   * ```js
   * // Reset Three.js state
   * threeRenderer.resetState();
   *
   * // Render a Three.js scene
   * threeRenderer.render(threeScene, threeCamera);
   *
   * // Reset PixiJS state since Three.js modified the WebGL context
   * pixiRenderer.resetState();
   *
   * // Now render Pixi content
   * pixiRenderer.render(pixiScene);
   * ```
   * @advanced
   */
  resetState() {
    this.runners.resetState.emit();
  }
};
_AbstractRenderer.defaultOptions = {
  /**
   * Default resolution / device pixel ratio of the renderer.
   * @default 1
   */
  resolution: 1,
  /**
   * Should the `failIfMajorPerformanceCaveat` flag be enabled as a context option used in the `isWebGLSupported`
   * function. If set to true, a WebGL renderer can fail to be created if the browser thinks there could be
   * performance issues when using WebGL.
   *
   * In PixiJS v6 this has changed from true to false by default, to allow WebGL to work in as many
   * scenarios as possible. However, some users may have a poor experience, for example, if a user has a gpu or
   * driver version blacklisted by the
   * browser.
   *
   * If your application requires high performance rendering, you may wish to set this to false.
   * We recommend one of two options if you decide to set this flag to false:
   *
   * 1: Use the Canvas renderer as a fallback in case high performance WebGL is
   *    not supported.
   *
   * 2: Call `isWebGLSupported` (which if found in the utils package) in your code before attempting to create a
   *    PixiJS renderer, and show an error message to the user if the function returns false, explaining that their
   *    device & browser combination does not support high performance WebGL.
   *    This is a much better strategy than trying to create a PixiJS renderer and finding it then fails.
   * @default false
   */
  failIfMajorPerformanceCaveat: false,
  /**
   * Should round pixels be forced when rendering?
   * @default false
   */
  roundPixels: false
};
var AbstractRenderer = _AbstractRenderer;

export {
  unsafeEvalSupported,
  loadEnvironmentExtensions,
  autoDetectEnvironment,
  CLEAR,
  SystemRunner,
  AbstractRenderer
};
