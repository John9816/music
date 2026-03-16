package com.music.player.ui.util

import android.graphics.Bitmap
import kotlin.math.max
import kotlin.math.min

object StackBlur {

    fun blur(source: Bitmap, radius: Int): Bitmap {
        val r = radius.coerceIn(1, 24)
        val bitmap = source.copy(Bitmap.Config.ARGB_8888, true)

        val w = bitmap.width
        val h = bitmap.height
        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)

        val div = r + r + 1
        val rsum = IntArray(w * h)
        val gsum = IntArray(w * h)
        val bsum = IntArray(w * h)

        val vmin = IntArray(max(w, h))
        val divsum = ((div + 1) shr 1).let { it * it }
        val dv = IntArray(256 * divsum)
        for (i in dv.indices) dv[i] = i / divsum

        var yi = 0
        var yw = 0

        val stack = IntArray(div * 3)
        val stackSize = div

        for (y in 0 until h) {
            var rinsum = 0
            var ginsum = 0
            var binsum = 0
            var routsum = 0
            var goutsum = 0
            var boutsum = 0
            var rtot = 0
            var gtot = 0
            var btot = 0

            for (i in -r..r) {
                val p = pixels[yi + min(w - 1, max(i, 0))]
                val sir = (i + r) * 3
                stack[sir] = (p shr 16) and 0xff
                stack[sir + 1] = (p shr 8) and 0xff
                stack[sir + 2] = p and 0xff
                val rbs = r + 1 - kotlin.math.abs(i)
                rtot += stack[sir] * rbs
                gtot += stack[sir + 1] * rbs
                btot += stack[sir + 2] * rbs
                if (i > 0) {
                    rinsum += stack[sir]
                    ginsum += stack[sir + 1]
                    binsum += stack[sir + 2]
                } else {
                    routsum += stack[sir]
                    goutsum += stack[sir + 1]
                    boutsum += stack[sir + 2]
                }
            }

            var stackPointer = r
            for (x in 0 until w) {
                rsum[yi] = dv[rtot.coerceIn(0, dv.lastIndex)]
                gsum[yi] = dv[gtot.coerceIn(0, dv.lastIndex)]
                bsum[yi] = dv[btot.coerceIn(0, dv.lastIndex)]

                rtot -= routsum
                gtot -= goutsum
                btot -= boutsum

                val stackStart = ((stackPointer - r + stackSize) % stackSize) * 3
                routsum -= stack[stackStart]
                goutsum -= stack[stackStart + 1]
                boutsum -= stack[stackStart + 2]

                if (y == 0) vmin[x] = min(x + r + 1, w - 1)
                val p = pixels[yw + vmin[x]]

                stack[stackStart] = (p shr 16) and 0xff
                stack[stackStart + 1] = (p shr 8) and 0xff
                stack[stackStart + 2] = p and 0xff

                rinsum += stack[stackStart]
                ginsum += stack[stackStart + 1]
                binsum += stack[stackStart + 2]

                rtot += rinsum
                gtot += ginsum
                btot += binsum

                stackPointer = (stackPointer + 1) % stackSize
                val sir = (stackPointer % stackSize) * 3

                routsum += stack[sir]
                goutsum += stack[sir + 1]
                boutsum += stack[sir + 2]

                rinsum -= stack[sir]
                ginsum -= stack[sir + 1]
                binsum -= stack[sir + 2]

                yi++
            }
            yw += w
        }

        for (x in 0 until w) {
            var rinsum = 0
            var ginsum = 0
            var binsum = 0
            var routsum = 0
            var goutsum = 0
            var boutsum = 0
            var rtot = 0
            var gtot = 0
            var btot = 0
            var yp = -r * w
            for (i in -r..r) {
                yi = max(0, yp) + x
                val sir = (i + r) * 3
                stack[sir] = rsum[yi]
                stack[sir + 1] = gsum[yi]
                stack[sir + 2] = bsum[yi]
                val rbs = r + 1 - kotlin.math.abs(i)
                rtot += rsum[yi] * rbs
                gtot += gsum[yi] * rbs
                btot += bsum[yi] * rbs
                if (i > 0) {
                    rinsum += stack[sir]
                    ginsum += stack[sir + 1]
                    binsum += stack[sir + 2]
                } else {
                    routsum += stack[sir]
                    goutsum += stack[sir + 1]
                    boutsum += stack[sir + 2]
                }
                if (i < h - 1) yp += w
            }

            var yi2 = x
            var stackPointer = r
            for (y in 0 until h) {
                val a = pixels[yi2] and -0x1000000
                val rOut = dv[rtot.coerceIn(0, dv.lastIndex)]
                val gOut = dv[gtot.coerceIn(0, dv.lastIndex)]
                val bOut = dv[btot.coerceIn(0, dv.lastIndex)]
                pixels[yi2] = a or (rOut shl 16) or (gOut shl 8) or bOut

                rtot -= routsum
                gtot -= goutsum
                btot -= boutsum

                val stackStart = ((stackPointer - r + stackSize) % stackSize) * 3
                routsum -= stack[stackStart]
                goutsum -= stack[stackStart + 1]
                boutsum -= stack[stackStart + 2]

                if (x == 0) vmin[y] = min(y + r + 1, h - 1) * w
                val p = x + vmin[y]

                stack[stackStart] = rsum[p]
                stack[stackStart + 1] = gsum[p]
                stack[stackStart + 2] = bsum[p]

                rinsum += stack[stackStart]
                ginsum += stack[stackStart + 1]
                binsum += stack[stackStart + 2]

                rtot += rinsum
                gtot += ginsum
                btot += binsum

                stackPointer = (stackPointer + 1) % stackSize
                val sir = (stackPointer % stackSize) * 3

                routsum += stack[sir]
                goutsum += stack[sir + 1]
                boutsum += stack[sir + 2]

                rinsum -= stack[sir]
                ginsum -= stack[sir + 1]
                binsum -= stack[sir + 2]

                yi2 += w
            }
        }

        bitmap.setPixels(pixels, 0, w, 0, 0, w, h)
        return bitmap
    }
}
