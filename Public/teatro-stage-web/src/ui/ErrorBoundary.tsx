import React from "react";

interface ErrorBoundaryState {
  hasError: boolean;
  message?: string;
}

export class ErrorBoundary extends React.Component<
  React.PropsWithChildren,
  ErrorBoundaryState
> {
  constructor(props: React.PropsWithChildren) {
    super(props);
    this.state = { hasError: false, message: undefined };
  }

  static getDerivedStateFromError(error: unknown): ErrorBoundaryState {
    return { hasError: true, message: (error as Error)?.message };
  }

  componentDidCatch(error: unknown, info: React.ErrorInfo): void {
    // eslint-disable-next-line no-console
    console.error("Stage app error", error, info);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div
          style={{
            padding: 24,
            fontFamily: "system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
            color: "#111",
            background: "#f4ead6",
            height: "100vh"
          }}
        >
          <h3>Stage app crashed</h3>
          <p>{this.state.message ?? "Unknown error"}</p>
          <p>Reload to retry. If this persists, the build is broken.</p>
        </div>
      );
    }
    return this.props.children;
  }
}
