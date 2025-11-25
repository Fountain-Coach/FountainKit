import React from "react";
import ReactDOM from "react-dom/client";
import { TeatroStageApp } from "./ui/TeatroStageApp";
import { ErrorBoundary } from "./ui/ErrorBoundary";

const rootElement = document.getElementById("root");

if (rootElement) {
  const root = ReactDOM.createRoot(rootElement);
  root.render(
    <ErrorBoundary>
      <TeatroStageApp />
    </ErrorBoundary>
  );
}
