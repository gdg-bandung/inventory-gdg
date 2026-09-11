import type { Config } from "tailwindcss";

export default {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        ink: "#12213a",
        navy: "#12325c",
        brand: "#2463eb",
        mist: "#f4f7fb",
      },
      boxShadow: {
        panel: "0 1px 2px rgba(16, 24, 40, .04), 0 10px 30px rgba(16, 24, 40, .05)",
      },
    },
  },
  plugins: [],
} satisfies Config;
