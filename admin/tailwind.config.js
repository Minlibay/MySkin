/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // Mirrors AppColors from the Flutter app.
        primary: '#F8E8EE',
        accent: '#D98FA3',
        background: '#FFF9FB',
        surface: '#FFFFFF',
        ink: '#2E2E2E',
        ink2: '#8E8E93',
        rose: { DEFAULT: '#6E2A37', deep: '#4D1F2A' },
        blush: { DEFAULT: '#FCEEF2', 2: '#F5DCE4' },
        champagne: '#F5EBDC',
        gold: '#D4A87A',
        sage: '#9BBFA5',
        success: '#6FA088',
        warning: '#C97D7D',
        info: '#5BA3D0',
      },
      fontFamily: {
        serif: ['"Cormorant Garamond"', 'Georgia', 'serif'],
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'monospace'],
      },
      boxShadow: {
        soft: '0 4px 20px rgba(217,143,163,0.08)',
        card: '0 8px 24px -8px rgba(217,143,163,0.18)',
        lift: '0 18px 40px -16px rgba(217,143,163,0.25)',
      },
      borderRadius: {
        '2xl': '20px',
        '3xl': '24px',
      },
    },
  },
  plugins: [],
};
