const defaultTheme = require('tailwindcss/defaultTheme');

/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./source/**/*.{html,erb,slim}",
    "./config.rb",
    "./lib/**/*.rb"
  ],
  safelist: [ 'hover:underline', 'hover:cursor-pointer', 'bg-blue-100'],
  theme: {

    extend: {
      screens: {
        print: { raw: 'print' },
        screen: { raw: 'screen' },
      },
      colors: {
        primary: "#27374D",
        secondary:"#526D82",
        accent: "#9DB2BF",
        active: "#2DB1BF",
        background: "#FEFEFE",
        background2: "#DDE6ED",
      },
      fontSize: {
        xs: '0.6rem',
        sm: '0.7rem',
        base: '0.8rem',
        lg: '0.85rem',
        xl: '1rem',
        '2xl': '1.4rem',
        '3xl': '1.7rem',
      },
      fontFamily: {
        sans: ['Inter var', ...defaultTheme.fontFamily.sans],
        serif: ['"Crimson Text"', 'serif'],
      },
      typography: {
        default: {
          css: {
            pre: false,
            code: false,
            'pre code': false,
            'code::before': false,
            'code::after': false,
          }
        }

      }
    },
  },
  plugins: [require('@tailwindcss/typography'),require("tailwindcss-animate"),],
};

