import React from "react";
import ReactDOM from "react-dom/client";
import { TeatroStageApp } from "./ui/TeatroStageApp";

const root = document.getElementById("root") as HTMLElement;

ReactDOM.createRoot(root).render(
  <React.StrictMode>
    <TeatroStageApp />
  </React.StrictMode>
);

