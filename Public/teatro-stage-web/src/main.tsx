import React from "react";
import ReactDOM from "react-dom/client";
import { TeatroStageApp } from "./ui/TeatroStageApp";

const rootElement = document.getElementById("root");

if (rootElement) {
  const root = ReactDOM.createRoot(rootElement);
  root.render(
    <React.StrictMode>
      <TeatroStageApp />
    </React.StrictMode>
  );
}

