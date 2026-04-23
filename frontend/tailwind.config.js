/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        bg:        '#0f1117',
        surface:   '#1a1d27',
        border:    '#2a2d3a',
        sidebar:   '#12151f',
        green:     '#00a651',
        blue:      '#00d4ff',
        textpri:   '#ffffff',
        textsec:   '#8b8fa8',
      },
      fontFamily: {
        sans: ['Inter', 'sans-serif'],
      },
      borderRadius: {
        card: '12px',
      },
    },
  },
  plugins: [],
}
