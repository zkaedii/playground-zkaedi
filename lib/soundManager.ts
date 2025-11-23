'use client';

import { Howl } from 'howler';

class SoundManager {
  private burnSound: Howl | null = null;
  private initialized = false;
  
  initialize() {
    if (this.initialized) return;
    
    // Create a synthetic burn sound using Web Audio API oscillators
    // This avoids needing external audio files
    this.initialized = true;
  }
  
  playBurnSound(intensity: number = 0.5) {
    if (typeof window === 'undefined') return;
    
    // Create synthetic sound with Web Audio API
    const AudioContextClass = window.AudioContext || (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AudioContextClass) return;
    
    const audioContext = new AudioContextClass();
    
    // Main oscillator for the "moan"
    const oscillator = audioContext.createOscillator();
    const gainNode = audioContext.createGain();
    
    // Low frequency for sultry effect
    oscillator.type = 'sine';
    oscillator.frequency.setValueAtTime(80, audioContext.currentTime);
    oscillator.frequency.exponentialRampToValueAtTime(60, audioContext.currentTime + 0.5);
    
    // Volume envelope
    const volume = Math.min(1, intensity * 0.3);
    gainNode.gain.setValueAtTime(0, audioContext.currentTime);
    gainNode.gain.linearRampToValueAtTime(volume, audioContext.currentTime + 0.1);
    gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 1.0);
    
    // Add some distortion for texture
    const filter = audioContext.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = 200;
    
    oscillator.connect(filter);
    filter.connect(gainNode);
    gainNode.connect(audioContext.destination);
    
    oscillator.start(audioContext.currentTime);
    oscillator.stop(audioContext.currentTime + 1.0);
  }
}

export const soundManager = new SoundManager();
