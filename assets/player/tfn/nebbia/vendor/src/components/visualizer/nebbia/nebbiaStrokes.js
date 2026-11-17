// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaStrokes.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
const STROKES_URL = new URL('../../../../../strokes.json', import.meta.url).href;
let loading = null;
let loaded = null;
export const loadNebbiaStrokes = ()=>{
    if (!loading) {
        loading = fetch(STROKES_URL).then((response)=>response.ok ? response.json() : null).catch(()=>null).then((data)=>{
            loaded = data && typeof data === 'object' ? data : null;
            return loaded;
        });
    }
    return loading;
};
export const getNebbiaStrokeMedians = (ch)=>loaded?.[ch] ?? null;
