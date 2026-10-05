import { resolveGeneratedAudio } from '@/lib/tts/audio-manifest'

let activeAudio: HTMLAudioElement | null = null

/**
 * Read a Japanese example sentence with generated VOICEVOX audio when it is
 * available, then fall back to the browser's speech synthesis API.
 *
 * Some browsers return an empty voice list until the asynchronous
 * `voiceschanged` event fires. If we speak before that happens, the browser
 * may choose the device's default (often Chinese) voice even when `lang` is
 * set to `ja-JP`. Wait for the voice list once, then explicitly select a
 * Japanese voice when one is available.
 */
export function speakJapanese(
  text: string,
  textbookId = 'builtin-japanese-syntax',
  explicitAudio?: string,
) {
  if (typeof window === 'undefined') return

  const synthesis = 'speechSynthesis' in window ? window.speechSynthesis : null
  const sentence = text.trim()
  if (!sentence) return

  activeAudio?.pause()
  activeAudio = null

  void (async () => {
    const generatedAudio = await resolveGeneratedAudio(sentence, textbookId, explicitAudio)
    if (generatedAudio) {
      const audio = new Audio(generatedAudio)
      activeAudio = audio
      try {
        synthesis?.cancel()
        await audio.play()
        return
      } catch {
        if (activeAudio === audio) activeAudio = null
      }
    }

    if (synthesis) speakWithBrowserVoice(sentence, synthesis)
  })()
}

function speakWithBrowserVoice(sentence: string, synthesis: SpeechSynthesis) {
  let spoken = false
  const speak = () => {
    if (spoken) return
    spoken = true

    const utterance = new SpeechSynthesisUtterance(sentence)
    utterance.lang = 'ja-JP'
    utterance.rate = 0.92

    const japaneseVoice = synthesis
      .getVoices()
      .find((voice) => /^ja(?:-|_)/i.test(voice.lang))

    if (japaneseVoice) utterance.voice = japaneseVoice

    synthesis.cancel()
    synthesis.speak(utterance)
  }

  const voices = synthesis.getVoices()
  if (voices.length > 0) {
    speak()
    return
  }

  let timeoutId: number | undefined
  const handleVoicesChanged = () => {
    if (timeoutId !== undefined) window.clearTimeout(timeoutId)
    synthesis.removeEventListener('voiceschanged', handleVoicesChanged)
    speak()
  }

  synthesis.addEventListener('voiceschanged', handleVoicesChanged)
  timeoutId = window.setTimeout(() => {
    synthesis.removeEventListener('voiceschanged', handleVoicesChanged)
    speak()
  }, 800)
}
