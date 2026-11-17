// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/textMeasureCache.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
export const rememberBounded = (cache, key, value, limit)=>{
    if (!cache.has(key) && cache.size >= limit) {
        const oldest = cache.keys().next();
        if (!oldest.done) cache.delete(oldest.value);
    }
    cache.set(key, value);
    return value;
};
export const measurePrefixOffsets = (graphemes, measurePrefix)=>{
    const offsets = new Array(graphemes.length + 1).fill(0);
    for(let count = 1; count <= graphemes.length; count += 1){
        offsets[count] = measurePrefix(graphemes.slice(0, count).join(''), count, offsets[count - 1]);
    }
    return offsets;
};
