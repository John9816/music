// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/types.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
export const NEBBIA_APPEAR_STYLES = [
    'write',
    'fade',
    'breath'
];
export const NEBBIA_FADE_STYLES = [
    'fog',
    'fingers'
];
export const NEBBIA_LAYOUTS = [
    'ribbon',
    'lines2',
    'lines3',
    'cross',
    'pillar',
    'header',
    'badge',
    'columns',
    'orbit'
];
export const NEBBIA_SCENERY = [
    'spot',
    'buildings',
    'lights',
    'cars',
    'road'
];
export const NEBBIA_RAIN = [
    'slant',
    'straight',
    'off'
];
export const NEBBIA_BEHIND = [
    'night',
    'aquarium',
    'backdrop'
];
export const NEBBIA_GLASS = [
    'rain',
    'dew',
    'snow'
];
export const NEBBIA_GLASS_FOR = {
    night: 'rain',
    aquarium: 'dew'
};
export const NEBBIA_MAX_JELLIES = 24;
export const NEBBIA_MAX_BURSTS = 12;
export const NEBBIA_LIMITS = {
    jitter: {
        min: 0,
        max: 1.5
    },
    warp: {
        min: 0,
        max: 1.5
    },
    mist: {
        min: 0.2,
        max: 1
    },
    hold: {
        min: 0,
        max: 6
    },
    refog: {
        min: 0.5,
        max: 12
    },
    strokeWidth: {
        min: 0.04,
        max: 0.16
    },
    writeSpeed: {
        min: 0.4,
        max: 2.5
    },
    doodle: {
        min: 0,
        max: 1
    },
    busSpeed: {
        min: 0,
        max: 3
    },
    neon: {
        min: 0,
        max: 2
    },
    spot: {
        min: 0,
        max: 2
    },
    spotX: {
        min: 0,
        max: 1
    },
    rainHit: {
        min: 0,
        max: 3
    },
    rainBig: {
        min: 0,
        max: 2
    },
    bump: {
        min: 0,
        max: 2.5
    },
    jellies: {
        min: 0,
        max: NEBBIA_MAX_JELLIES
    },
    jellySize: {
        min: 0.5,
        max: 1.8
    },
    bubbles: {
        min: 0,
        max: 1
    },
    dew: {
        min: 0,
        max: 1.5
    },
    dewSize: {
        min: 0.5,
        max: 2
    },
    dewGlint: {
        min: 0,
        max: 2
    },
    snow: {
        min: 0,
        max: 3
    },
    snowSize: {
        min: 0.5,
        max: 2
    },
    snowMelt: {
        min: 0.25,
        max: 3
    }
};
export const DEFAULT_NEBBIA_TUNING = {
    render: {
        scale: 'global',
        antialias: 'global'
    },
    appear: [
        'write',
        'fade'
    ],
    fade: [
        'fog'
    ],
    layouts: [
        ...NEBBIA_LAYOUTS
    ],
    behind: 'night',
    glass: 'rain',
    scenery: [
        ...NEBBIA_SCENERY
    ],
    rain: 'slant',
    credits: true,
    jitter: 0.6,
    warp: 0.6,
    mist: 0.75,
    hold: 1.2,
    refog: 4,
    strokeWidth: 0.09,
    writeSpeed: 1,
    doodle: 0.3,
    busSpeed: 1,
    neon: 1,
    spot: 0.5,
    spotX: 0.8,
    rainHit: 1,
    rainBig: 1,
    bump: 1,
    jellies: 16,
    jellySize: 1,
    bubbles: 0.6,
    dew: 1,
    dewSize: 1,
    dewGlint: 1,
    snow: 1,
    snowSize: 1,
    snowMelt: 1
};
