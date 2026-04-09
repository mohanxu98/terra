// Type declaration for importing WGSL shader files as raw strings via Vite
declare module '*.wgsl?raw' {
  const content: string;
  export default content;
}
