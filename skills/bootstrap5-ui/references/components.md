# Bootstrap 5 Component Patterns

## Table of Contents
- [Modals](#modals)
- [Alerts and Toasts](#alerts-and-toasts)
- [Accordion](#accordion)
- [Offcanvas](#offcanvas)
- [Buttons and Button Groups](#buttons-and-button-groups)
- [Badges](#badges)
- [Progress and Spinners](#progress-and-spinners)
- [List Groups](#list-groups)
- [Tabs and Pills](#tabs-and-pills)
- [Tooltips and Popovers](#tooltips-and-popovers)
- [Carousel](#carousel)
- [Dropdowns](#dropdowns)
- [Typography Patterns](#typography-patterns)
- [Image Patterns](#image-patterns)
- [Common Page Layouts](#common-page-layouts)

## Modals

### Standard Modal

```html
<!-- Trigger -->
<button type="button" class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#exampleModal">
    Open Modal
</button>

<!-- Modal -->
<div class="modal fade" id="exampleModal" tabindex="-1" aria-labelledby="exampleModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="exampleModalLabel">Modal Title</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                <p>Modal body content here.</p>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
                <button type="button" class="btn btn-primary">Save changes</button>
            </div>
        </div>
    </div>
</div>
```

### Modal Sizes
- `.modal-sm` — 300px max-width
- Default — 500px max-width
- `.modal-lg` — 800px max-width
- `.modal-xl` — 1140px max-width
- `.modal-fullscreen` — full viewport

```html
<div class="modal-dialog modal-lg">...</div>
<div class="modal-dialog modal-fullscreen-md-down">...</div> <!-- Fullscreen below md -->
```

### Scrollable Modal with Static Backdrop

```html
<div class="modal fade" data-bs-backdrop="static" data-bs-keyboard="false" tabindex="-1">
    <div class="modal-dialog modal-dialog-scrollable modal-dialog-centered">
        <div class="modal-content">...</div>
    </div>
</div>
```

### Modal via JavaScript

```javascript
const modal = new bootstrap.Modal(document.getElementById('myModal'));
modal.show();
// modal.hide();
// modal.toggle();

// Listen for events
document.getElementById('myModal').addEventListener('hidden.bs.modal', () => {
    // Cleanup after close
});
```

## Alerts and Toasts

### Dismissible Alert

```html
<div class="alert alert-success alert-dismissible fade show" role="alert">
    <strong>Success!</strong> Your changes have been saved.
    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
</div>

<!-- Alert variants: alert-primary, alert-secondary, alert-success, alert-danger,
     alert-warning, alert-info, alert-light, alert-dark -->

<!-- Alert with icon and additional content -->
<div class="alert alert-warning d-flex align-items-center" role="alert">
    <svg class="bi flex-shrink-0 me-2" width="24" height="24"><use xlink:href="#exclamation-triangle-fill"/></svg>
    <div>
        <h6 class="alert-heading mb-1">Warning!</h6>
        An example alert with an icon and heading.
    </div>
</div>
```

### Toast Notifications

```html
<!-- Toast container — position fixed in corner -->
<div class="toast-container position-fixed bottom-0 end-0 p-3" style="z-index: 11">
    <div id="successToast" class="toast align-items-center text-bg-success border-0" role="alert"
         aria-live="assertive" aria-atomic="true">
        <div class="d-flex">
            <div class="toast-body">Record saved successfully.</div>
            <button type="button" class="btn-close btn-close-white me-2 m-auto"
                    data-bs-dismiss="toast" aria-label="Close"></button>
        </div>
    </div>
</div>
```

Show toast via JS:
```javascript
const toast = new bootstrap.Toast(document.getElementById('successToast'));
toast.show();
```

### Toast with Header

```html
<div class="toast" role="alert" aria-live="assertive" aria-atomic="true">
    <div class="toast-header">
        <strong class="me-auto">Notification</strong>
        <small class="text-body-secondary">just now</small>
        <button type="button" class="btn-close" data-bs-dismiss="toast" aria-label="Close"></button>
    </div>
    <div class="toast-body">Your order has been placed.</div>
</div>
```

## Accordion

```html
<div class="accordion" id="faqAccordion">
    <div class="accordion-item">
        <h2 class="accordion-header">
            <button class="accordion-button" type="button"
                    data-bs-toggle="collapse" data-bs-target="#collapseOne"
                    aria-expanded="true" aria-controls="collapseOne">
                Question #1
            </button>
        </h2>
        <div id="collapseOne" class="accordion-collapse collapse show"
             data-bs-parent="#faqAccordion">
            <div class="accordion-body">Answer to question #1.</div>
        </div>
    </div>
    <div class="accordion-item">
        <h2 class="accordion-header">
            <button class="accordion-button collapsed" type="button"
                    data-bs-toggle="collapse" data-bs-target="#collapseTwo"
                    aria-expanded="false" aria-controls="collapseTwo">
                Question #2
            </button>
        </h2>
        <div id="collapseTwo" class="accordion-collapse collapse"
             data-bs-parent="#faqAccordion">
            <div class="accordion-body">Answer to question #2.</div>
        </div>
    </div>
</div>
```

**Flush variant:** Add `.accordion-flush` to remove borders and rounded corners.

**Always-open:** Remove `data-bs-parent` to allow multiple items open simultaneously.

## Offcanvas

```html
<!-- Trigger -->
<button class="btn btn-primary" type="button" data-bs-toggle="offcanvas"
        data-bs-target="#sidePanel" aria-controls="sidePanel">
    Open Filters
</button>

<!-- Offcanvas -->
<div class="offcanvas offcanvas-start" tabindex="-1" id="sidePanel"
     aria-labelledby="sidePanelLabel">
    <div class="offcanvas-header">
        <h5 class="offcanvas-title" id="sidePanelLabel">Filters</h5>
        <button type="button" class="btn-close" data-bs-dismiss="offcanvas" aria-label="Close"></button>
    </div>
    <div class="offcanvas-body">
        <p>Filter content here.</p>
    </div>
</div>
```

**Placement:** `offcanvas-start` (left), `offcanvas-end` (right), `offcanvas-top`, `offcanvas-bottom`

**Responsive:** `offcanvas-lg` — offcanvas below lg breakpoint, visible inline above lg.

## Buttons and Button Groups

### Button Variants

```html
<!-- Solid -->
<button class="btn btn-primary">Primary</button>
<button class="btn btn-secondary">Secondary</button>
<button class="btn btn-success">Success</button>
<button class="btn btn-danger">Danger</button>
<button class="btn btn-warning">Warning</button>
<button class="btn btn-info">Info</button>

<!-- Outline -->
<button class="btn btn-outline-primary">Outline Primary</button>

<!-- Sizes -->
<button class="btn btn-primary btn-lg">Large</button>
<button class="btn btn-primary btn-sm">Small</button>

<!-- Loading state -->
<button class="btn btn-primary" type="button" disabled>
    <span class="spinner-border spinner-border-sm" aria-hidden="true"></span>
    <span role="status">Loading...</span>
</button>
```

### Button Group

```html
<div class="btn-group" role="group" aria-label="Actions">
    <button type="button" class="btn btn-outline-primary">View</button>
    <button type="button" class="btn btn-outline-primary">Edit</button>
    <button type="button" class="btn btn-outline-danger">Delete</button>
</div>
```

### Button Toolbar

```html
<div class="btn-toolbar justify-content-between" role="toolbar" aria-label="Toolbar with button groups">
    <div class="btn-group" role="group">
        <button type="button" class="btn btn-outline-secondary">Bold</button>
        <button type="button" class="btn btn-outline-secondary">Italic</button>
    </div>
    <div class="input-group">
        <div class="input-group-text">@</div>
        <input type="text" class="form-control" placeholder="Username">
    </div>
</div>
```

## Badges

```html
<!-- Inline badge -->
<h4>Messages <span class="badge text-bg-primary">4</span></h4>

<!-- Pill badge -->
<span class="badge rounded-pill text-bg-success">Active</span>
<span class="badge rounded-pill text-bg-danger">Expired</span>
<span class="badge rounded-pill text-bg-warning">Pending</span>

<!-- Badge in button -->
<button type="button" class="btn btn-primary position-relative">
    Inbox
    <span class="position-absolute top-0 start-100 translate-middle badge rounded-pill bg-danger">
        99+
        <span class="visually-hidden">unread messages</span>
    </span>
</button>
```

## Progress and Spinners

### Progress Bars

```html
<!-- Basic -->
<div class="progress" role="progressbar" aria-valuenow="75" aria-valuemin="0" aria-valuemax="100">
    <div class="progress-bar" style="width: 75%">75%</div>
</div>

<!-- Striped and animated -->
<div class="progress">
    <div class="progress-bar progress-bar-striped progress-bar-animated bg-success" style="width: 50%"></div>
</div>

<!-- Stacked -->
<div class="progress-stacked">
    <div class="progress" role="progressbar" style="width: 15%">
        <div class="progress-bar">15%</div>
    </div>
    <div class="progress" role="progressbar" style="width: 30%">
        <div class="progress-bar bg-success">30%</div>
    </div>
    <div class="progress" role="progressbar" style="width: 20%">
        <div class="progress-bar bg-info">20%</div>
    </div>
</div>
```

### Spinners

```html
<!-- Border spinner -->
<div class="spinner-border text-primary" role="status">
    <span class="visually-hidden">Loading...</span>
</div>

<!-- Growing spinner -->
<div class="spinner-grow text-success" role="status">
    <span class="visually-hidden">Loading...</span>
</div>

<!-- Small spinner in button -->
<button class="btn btn-primary" type="button" disabled>
    <span class="spinner-border spinner-border-sm" aria-hidden="true"></span>
    Saving...
</button>

<!-- Centered full-page loader -->
<div class="d-flex justify-content-center align-items-center" style="min-height: 300px;">
    <div class="spinner-border" role="status">
        <span class="visually-hidden">Loading...</span>
    </div>
</div>
```

## List Groups

```html
<!-- Basic -->
<ul class="list-group">
    <li class="list-group-item active" aria-current="true">Active item</li>
    <li class="list-group-item">Second item</li>
    <li class="list-group-item">Third item</li>
</ul>

<!-- Actionable with badges -->
<div class="list-group">
    <a href="#" class="list-group-item list-group-item-action d-flex justify-content-between align-items-center">
        Messages
        <span class="badge text-bg-primary rounded-pill">14</span>
    </a>
    <a href="#" class="list-group-item list-group-item-action d-flex justify-content-between align-items-center">
        Orders
        <span class="badge text-bg-primary rounded-pill">2</span>
    </a>
</div>

<!-- Custom content -->
<div class="list-group">
    <a href="#" class="list-group-item list-group-item-action">
        <div class="d-flex w-100 justify-content-between">
            <h6 class="mb-1">List group item heading</h6>
            <small class="text-body-secondary">3 days ago</small>
        </div>
        <p class="mb-1">Some placeholder content.</p>
        <small class="text-body-secondary">Additional metadata.</small>
    </a>
</div>
```

## Tabs and Pills

### Tabs with Content Panels

```html
<ul class="nav nav-tabs" id="myTab" role="tablist">
    <li class="nav-item" role="presentation">
        <button class="nav-link active" id="home-tab" data-bs-toggle="tab"
                data-bs-target="#home-panel" type="button" role="tab"
                aria-controls="home-panel" aria-selected="true">Home</button>
    </li>
    <li class="nav-item" role="presentation">
        <button class="nav-link" id="profile-tab" data-bs-toggle="tab"
                data-bs-target="#profile-panel" type="button" role="tab"
                aria-controls="profile-panel" aria-selected="false">Profile</button>
    </li>
</ul>
<div class="tab-content" id="myTabContent">
    <div class="tab-pane fade show active" id="home-panel" role="tabpanel"
         aria-labelledby="home-tab" tabindex="0">
        <div class="p-3">Home content here.</div>
    </div>
    <div class="tab-pane fade" id="profile-panel" role="tabpanel"
         aria-labelledby="profile-tab" tabindex="0">
        <div class="p-3">Profile content here.</div>
    </div>
</div>
```

### Pills Navigation

```html
<ul class="nav nav-pills mb-3">
    <li class="nav-item">
        <a class="nav-link active" href="#">Active</a>
    </li>
    <li class="nav-item">
        <a class="nav-link" href="#">Link</a>
    </li>
</ul>
```

### Vertical Pills

```html
<div class="d-flex align-items-start">
    <div class="nav flex-column nav-pills me-3" role="tablist" aria-orientation="vertical">
        <button class="nav-link active" data-bs-toggle="pill" data-bs-target="#v-tab1"
                type="button" role="tab">Tab 1</button>
        <button class="nav-link" data-bs-toggle="pill" data-bs-target="#v-tab2"
                type="button" role="tab">Tab 2</button>
    </div>
    <div class="tab-content">
        <div class="tab-pane fade show active" id="v-tab1" role="tabpanel">Content 1</div>
        <div class="tab-pane fade" id="v-tab2" role="tabpanel">Content 2</div>
    </div>
</div>
```

## Tooltips and Popovers

### Tooltips

Require initialization:
```javascript
document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(el => {
    new bootstrap.Tooltip(el);
});
```

```html
<button type="button" class="btn btn-secondary" data-bs-toggle="tooltip"
        data-bs-placement="top" title="Tooltip text">
    Hover me
</button>
```

### Popovers

Require initialization:
```javascript
document.querySelectorAll('[data-bs-toggle="popover"]').forEach(el => {
    new bootstrap.Popover(el);
});
```

```html
<button type="button" class="btn btn-lg btn-danger" data-bs-toggle="popover"
        data-bs-title="Popover title" data-bs-content="Popover body content."
        data-bs-trigger="focus">
    Click me
</button>
```

## Carousel

```html
<div id="heroCarousel" class="carousel slide" data-bs-ride="carousel">
    <div class="carousel-indicators">
        <button type="button" data-bs-target="#heroCarousel" data-bs-slide-to="0"
                class="active" aria-current="true" aria-label="Slide 1"></button>
        <button type="button" data-bs-target="#heroCarousel" data-bs-slide-to="1"
                aria-label="Slide 2"></button>
    </div>
    <div class="carousel-inner">
        <div class="carousel-item active">
            <img src="..." class="d-block w-100" alt="...">
            <div class="carousel-caption d-none d-md-block">
                <h5>First slide</h5>
                <p>Description text.</p>
            </div>
        </div>
        <div class="carousel-item">
            <img src="..." class="d-block w-100" alt="...">
        </div>
    </div>
    <button class="carousel-control-prev" type="button" data-bs-target="#heroCarousel" data-bs-slide="prev">
        <span class="carousel-control-prev-icon" aria-hidden="true"></span>
        <span class="visually-hidden">Previous</span>
    </button>
    <button class="carousel-control-next" type="button" data-bs-target="#heroCarousel" data-bs-slide="next">
        <span class="carousel-control-next-icon" aria-hidden="true"></span>
        <span class="visually-hidden">Next</span>
    </button>
</div>
```

## Dropdowns

```html
<!-- Standard dropdown -->
<div class="dropdown">
    <button class="btn btn-secondary dropdown-toggle" type="button"
            data-bs-toggle="dropdown" aria-expanded="false">
        Options
    </button>
    <ul class="dropdown-menu">
        <li><h6 class="dropdown-header">Section</h6></li>
        <li><a class="dropdown-item" href="#">Action</a></li>
        <li><a class="dropdown-item active" href="#">Active item</a></li>
        <li><a class="dropdown-item disabled" aria-disabled="true">Disabled</a></li>
        <li><hr class="dropdown-divider"></li>
        <li><a class="dropdown-item text-danger" href="#">Delete</a></li>
    </ul>
</div>

<!-- Dropdown directions: dropup, dropend, dropstart -->
<div class="dropup">
    <button class="btn btn-secondary dropdown-toggle" data-bs-toggle="dropdown">Dropup</button>
    <ul class="dropdown-menu">...</ul>
</div>

<!-- Auto-close behavior -->
<div class="dropdown">
    <button class="btn btn-secondary dropdown-toggle" data-bs-toggle="dropdown"
            data-bs-auto-close="outside">Click outside to close</button>
    <ul class="dropdown-menu">...</ul>
</div>
```

## Typography Patterns

```html
<!-- Display headings -->
<h1 class="display-1">Display 1</h1>
<h1 class="display-4">Display 4</h1>

<!-- Lead paragraph -->
<p class="lead">This is a lead paragraph with larger font.</p>

<!-- Text utilities -->
<p class="text-body-secondary">Muted secondary text</p>
<p class="text-body-emphasis">Emphasized text</p>
<p class="fw-bold">Bold text</p>
<p class="fst-italic">Italic text</p>
<p class="text-decoration-underline">Underlined</p>
<p class="text-truncate" style="max-width: 150px;">Long text that truncates</p>

<!-- Blockquote -->
<figure>
    <blockquote class="blockquote">
        <p>A well-known quote.</p>
    </blockquote>
    <figcaption class="blockquote-footer">
        Author in <cite title="Source">Source Title</cite>
    </figcaption>
</figure>
```

## Image Patterns

```html
<!-- Responsive image -->
<img src="..." class="img-fluid" alt="Responsive image">

<!-- Thumbnail -->
<img src="..." class="img-thumbnail" alt="Thumbnail">

<!-- Rounded -->
<img src="..." class="rounded" alt="Rounded image">

<!-- Figure with caption -->
<figure class="figure">
    <img src="..." class="figure-img img-fluid rounded" alt="A caption">
    <figcaption class="figure-caption text-end">A caption for the image.</figcaption>
</figure>
```

## Common Page Layouts

### Dashboard Layout

```html
<div class="container-fluid">
    <div class="row">
        <!-- Sidebar -->
        <nav class="col-md-3 col-lg-2 d-md-block bg-body-tertiary sidebar collapse" id="sidebarMenu">
            <div class="position-sticky pt-3">
                <ul class="nav flex-column">
                    <li class="nav-item">
                        <a class="nav-link active" aria-current="page" href="#">Dashboard</a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="#">Orders</a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="#">Products</a>
                    </li>
                </ul>
            </div>
        </nav>

        <!-- Main content -->
        <main class="col-md-9 ms-sm-auto col-lg-10 px-md-4">
            <div class="d-flex justify-content-between flex-wrap flex-md-nowrap align-items-center pt-3 pb-2 mb-3 border-bottom">
                <h1 class="h2">Dashboard</h1>
                <div class="btn-toolbar mb-2 mb-md-0">
                    <div class="btn-group me-2">
                        <button type="button" class="btn btn-sm btn-outline-secondary">Share</button>
                        <button type="button" class="btn btn-sm btn-outline-secondary">Export</button>
                    </div>
                </div>
            </div>

            <!-- Stats cards -->
            <div class="row row-cols-1 row-cols-sm-2 row-cols-xl-4 g-3 mb-4">
                <div class="col">
                    <div class="card">
                        <div class="card-body">
                            <h6 class="card-subtitle mb-2 text-body-secondary">Total Revenue</h6>
                            <h3 class="card-title mb-0">$45,231</h3>
                        </div>
                    </div>
                </div>
                <!-- repeat for other stats -->
            </div>

            <!-- Content area -->
            @RenderBody()
        </main>
    </div>
</div>
```

### Hero Section

```html
<div class="px-4 py-5 my-5 text-center">
    <h1 class="display-5 fw-bold text-body-emphasis">Welcome to MyApp</h1>
    <div class="col-lg-6 mx-auto">
        <p class="lead mb-4">Quickly design and customize responsive mobile-first sites.</p>
        <div class="d-grid gap-2 d-sm-flex justify-content-sm-center">
            <a href="#" class="btn btn-primary btn-lg px-4 gap-3">Get started</a>
            <a href="#" class="btn btn-outline-secondary btn-lg px-4">Learn more</a>
        </div>
    </div>
</div>
```

### Pricing Cards

```html
<div class="row row-cols-1 row-cols-md-3 mb-3 text-center g-4">
    <div class="col">
        <div class="card mb-4 rounded-3 shadow-sm">
            <div class="card-header py-3">
                <h4 class="my-0 fw-normal">Free</h4>
            </div>
            <div class="card-body">
                <h1 class="card-title">$0<small class="text-body-secondary fw-light">/mo</small></h1>
                <ul class="list-unstyled mt-3 mb-4">
                    <li>10 users included</li>
                    <li>2 GB of storage</li>
                    <li>Email support</li>
                </ul>
                <button type="button" class="w-100 btn btn-lg btn-outline-primary">Sign up for free</button>
            </div>
        </div>
    </div>
    <div class="col">
        <div class="card mb-4 rounded-3 shadow-sm border-primary">
            <div class="card-header py-3 text-bg-primary border-primary">
                <h4 class="my-0 fw-normal">Pro</h4>
            </div>
            <div class="card-body">
                <h1 class="card-title">$15<small class="text-body-secondary fw-light">/mo</small></h1>
                <ul class="list-unstyled mt-3 mb-4">
                    <li>20 users included</li>
                    <li>10 GB of storage</li>
                    <li>Priority email support</li>
                </ul>
                <button type="button" class="w-100 btn btn-lg btn-primary">Get started</button>
            </div>
        </div>
    </div>
</div>
```

### Login Page

```html
<div class="d-flex align-items-center py-4 bg-body-tertiary min-vh-100">
    <main class="form-signin w-100 m-auto" style="max-width: 330px;">
        <form method="post">
            <h1 class="h3 mb-3 fw-normal text-center">Please sign in</h1>

            <div class="form-floating mb-2">
                <input type="email" class="form-control" id="email" placeholder="name@example.com">
                <label for="email">Email address</label>
            </div>
            <div class="form-floating mb-3">
                <input type="password" class="form-control" id="password" placeholder="Password">
                <label for="password">Password</label>
            </div>

            <div class="form-check text-start mb-3">
                <input class="form-check-input" type="checkbox" value="remember-me" id="rememberMe">
                <label class="form-check-label" for="rememberMe">Remember me</label>
            </div>
            <button class="btn btn-primary w-100 py-2" type="submit">Sign in</button>
        </form>
    </main>
</div>
```
