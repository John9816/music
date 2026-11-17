// Adapted from Folia 5bdade1102f9b80830eec5f523e87f3e2a13d40d; src/components/visualizer/nebbia/nebbiaFogGl.ts
// Copyright Folia contributors. AGPL-3.0-only. See app/THIRD_PARTY_NOTICES.md.
import { FOG_DIV } from './nebbiaConstants.js';
import { makeTex } from './nebbiaGlUtils.js';
const SHARP_DIV = 4;
export class NebbiaFogGl {
    gl;
    ok;
    layers;
    constructor(gl, unit, ok, sharpUnit = null){
        this.gl = gl;
        this.ok = ok;
        this.layers = [
            {
                tex: makeTex(gl, unit),
                fb: ok ? gl.createFramebuffer() : null,
                div: FOG_DIV,
                b: 0.03,
                w: 1,
                h: 1
            },
            {
                tex: makeTex(gl, unit + 1),
                fb: ok ? gl.createFramebuffer() : null,
                div: FOG_DIV * 2,
                b: 0.09,
                w: 1,
                h: 1
            }
        ];
        if (ok && sharpUnit !== null) this.layers.push({
            tex: makeTex(gl, sharpUnit),
            fb: gl.createFramebuffer(),
            div: SHARP_DIV,
            b: 0.006,
            w: 1,
            h: 1
        });
    }
    resize(canvasW, canvasH) {
        const { gl } = this;
        if (!this.ok) return;
        for (const L of this.layers){
            L.w = Math.max(1, Math.ceil(canvasW / L.div));
            L.h = Math.max(1, Math.ceil(canvasH / L.div));
            gl.activeTexture(gl.TEXTURE0 + L.tex.unit);
            gl.bindTexture(gl.TEXTURE_2D, L.tex.t);
            gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, L.w, L.h, 0, gl.RGBA, gl.HALF_FLOAT, null);
            gl.bindFramebuffer(gl.FRAMEBUFFER, L.fb);
            gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, L.tex.t, 0);
        }
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    }
    draw(uFogB) {
        const { gl } = this;
        if (!this.ok) return;
        for (const L of this.layers){
            gl.bindFramebuffer(gl.FRAMEBUFFER, L.fb);
            gl.viewport(0, 0, L.w, L.h);
            gl.uniform1f(uFogB, L.b);
            gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
        }
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    }
}
