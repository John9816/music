package com.music.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioSpectrumFftTest {
    @Test
    fun silenceAndDcDoNotCreateMusicEnergy() {
        val fft = ByteArray(1024)
        fft[0] = 127 // DC component; not an audible frequency bin.
        fft[1] = 127 // Nyquist coefficient, not the imaginary part of DC.
        val bands = AudioSpectrumFft.bands(fft, 44_100_000)
        assertEquals(32, bands.size)
        assertTrue(bands.all { it == 0.0 })
    }

    @Test
    fun signedRealAndImaginaryValuesHaveEqualMagnitude() {
        val real = ByteArray(1024)
        real[32] = -100
        val imaginary = ByteArray(1024)
        imaginary[33] = 100
        val realBands = AudioSpectrumFft.bands(real, 44_100_000)
        val imaginaryBands = AudioSpectrumFft.bands(imaginary, 44_100_000)
        assertTrue(realBands.any { it > 0.0 })
        realBands.indices.forEach {
            assertEquals(realBands[it], imaginaryBands[it], 0.000001)
        }
    }

    @Test
    fun higherFrequencyEnergyMovesToHigherBands() {
        val low = ByteArray(1024).also { it[8] = 127 }
        val high = ByteArray(1024).also { it[256] = 127 }
        val lowBands = AudioSpectrumFft.bands(low, 44_100_000)
        val highBands = AudioSpectrumFft.bands(high, 44_100_000)
        assertTrue(lowBands.indexOfFirst { it > 0 } < highBands.indexOfFirst { it > 0 })
        assertTrue(highBands.all { it.isFinite() && it in 0.0..1.0 })
    }

    @Test
    fun malformedBuffersAndUnknownRatesStaySilent() {
        assertTrue(AudioSpectrumFft.bands(byteArrayOf(127), 44_100_000).all { it == 0.0 })
        assertTrue(AudioSpectrumFft.bands(ByteArray(1024) { 127 }, 0).all { it == 0.0 })
    }
}
