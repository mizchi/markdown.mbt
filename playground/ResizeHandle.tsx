import { onCleanup } from '@luna_ui/luna';

interface ResizeHandleProps {
  label: string;
  class: string;
  value: () => number;
  min: () => number;
  max: () => number;
  onDelta: (pixels: number) => void;
  onCommit: () => void;
}

export function ResizeHandle(props: ResizeHandleProps) {
  let previousX: number | null = null;
  let previousCursor = '';
  let previousSelection = '';
  const finish = () => {
    if (previousX === null) return;
    previousX = null;
    document.body.style.cursor = previousCursor;
    document.body.style.userSelect = previousSelection;
    props.onCommit();
  };
  onCleanup(() => { finish(); });
  return <div
    class={`resize-handle ${props.class}`}
    role="separator"
    aria-label={props.label}
    aria-orientation="vertical"
    aria-valuenow={props.value}
    aria-valuemin={props.min}
    aria-valuemax={props.max}
    tabIndex={0}
    onPointerDown={(event: PointerEvent) => {
      if (event.button !== 0) return;
      event.preventDefault();
      (event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
      previousX = event.clientX;
      previousCursor = document.body.style.cursor;
      previousSelection = document.body.style.userSelect;
      document.body.style.cursor = 'col-resize';
      document.body.style.userSelect = 'none';
    }}
    onPointerMove={(event: PointerEvent) => {
      if (previousX === null) return;
      const delta = event.clientX - previousX;
      previousX = event.clientX;
      props.onDelta(delta);
    }}
    onPointerUp={finish}
    onPointerCancel={finish}
    onLostPointerCapture={finish}
    onKeyDown={(event: KeyboardEvent) => {
      if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
      event.preventDefault();
      props.onDelta(event.key === 'ArrowLeft' ? -16 : 16);
      props.onCommit();
    }}
  />;
}
