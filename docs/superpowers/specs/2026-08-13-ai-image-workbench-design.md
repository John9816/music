# AI Image Workbench Design

## Goal

Redesign the AI image page around the documented asynchronous image APIs while preserving a focused creation flow on desktop and a comfortable single-column flow on mobile.

## Direction

The page uses the approved C layout with the A "darkroom white" visual language: a warm paper background, deep ink-green text, muted red-orange action color, thin structural rules, and restrained corner radii. The distinctive element is a quiet image canvas that remains the visual anchor while controls and recovery work stay close at hand.

## Structure

- Header tabs switch between Generate, Edit, and History.
- Main workbench uses a responsive split: result canvas and prompt/action on the left, model/size/count/source controls on the right.
- On narrow screens the split becomes one column: canvas, prompt/action, then a collapsible parameter section.
- A bottom work queue shows resumable pending/processing/failed tasks and a History entry. On mobile it becomes a horizontally scrollable strip.
- History is paginated and supports share toggle, delete, and retry for failed records.

## API/Data Flow

Use `/api/user/image/models`, `/generate`, `/edit`, `/generate/{taskId}`, `/tasks`, and `/history`. Generate/edit submits an async task, polls it to completion, and refreshes history. Initial load restores resumable tasks and the first history page. HTTP 403/429 messages are surfaced directly through the existing `ApiException` path.

## Responsive and Accessibility

Use `LayoutBuilder` with a breakpoint around 760 logical pixels. Keep controls at least 44 logical pixels high, preserve visible focus states through existing Material components, and honor reduced-motion platform behavior by avoiding required animation for task status.

## Testing

Extend AI API tests for task/history parsing and mutation endpoints. Add widget coverage for generate/edit mode, mobile single-column layout, model/size/count submission fields, and failed-task retry affordance.
