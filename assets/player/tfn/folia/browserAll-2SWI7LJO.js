// Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; adapted for TuneFreeNext. See THIRD_PARTY_NOTICES.md and scripts/vendor_folia_skins.mjs.
import "./chunk-VYGQJBIC.js";
import {
  AccessibilitySystem,
  DOMPipe,
  EventSystem,
  FederatedContainer,
  accessibilityTarget
} from "./chunk-R5LEVDJH.js";
import "./chunk-ZWBN2NC7.js";
import "./chunk-Q62SMUSG.js";
import {
  Container
} from "./chunk-RMIIME3Z.js";
import "./chunk-J57BYMP5.js";
import "./chunk-XQE2JCH6.js";
import "./chunk-2SNS7NNO.js";
import {
  extensions
} from "./chunk-NJ7XHR5M.js";

// scripts/folia/node_modules/pixi.js/lib/accessibility/init.mjs
extensions.add(AccessibilitySystem);
extensions.mixin(Container, accessibilityTarget);

// scripts/folia/node_modules/pixi.js/lib/dom/init.mjs
extensions.add(DOMPipe);

// scripts/folia/node_modules/pixi.js/lib/events/init.mjs
extensions.add(EventSystem);
extensions.mixin(Container, FederatedContainer);
