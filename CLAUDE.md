# CLAUDE.md - AI Assistant Development Guide

## Project Overview

**Pacific** is a static website for a seafood restaurant featuring a modern, responsive single-page design. The site showcases the restaurant's menu (brunch, dinner, and drinks), location information, an image gallery, and a reservation system with modal functionality.

**Repository**: serksnas
**Type**: Static Website (HTML/CSS/JavaScript)
**Target**: Restaurant/Hospitality Industry
**Branch Convention**: Feature branches follow the pattern `claude/*`

---

## Codebase Structure

```
serksnas/
├── index.html          # Main HTML file - single-page application
├── css/
│   └── style.css       # All styling, including responsive design
├── js/
│   └── main.js         # jQuery-based interactions and animations
├── images/             # All visual assets (photos, maps, carousel images)
│   ├── home-header.jpg
│   ├── gallery-header.jpg
│   ├── carousel-*.jpg  # Gallery carousel images (1-4)
│   ├── map.png         # Location map
│   └── [menu-images]   # Food and drink photography
└── README.md           # Basic project description
```

### File Organization

- **Single HTML file**: All content is contained in `index.html`
- **Single CSS file**: All styles are in `css/style.css`
- **Single JS file**: All interactions are in `js/main.js`
- **Images directory**: Contains 22+ high-resolution images for various sections

---

## Technology Stack

### Core Technologies
- **HTML5**: Semantic markup structure
- **CSS3**: Grid layout, flexbox, transitions, responsive design
- **JavaScript**: jQuery 3.2.1 for DOM manipulation and animations

### External Dependencies
- **jQuery 3.2.1**: Loaded via CDN
  - Source: `https://code.jquery.com/jquery-3.2.1.min.js`
- **Font Awesome 4.7.0**: Icon library for social media icons
  - Source: `https://maxcdn.bootstrapcdn.com/font-awesome/4.7.0/css/font-awesome.min.css`

### Design Patterns
- **Single-Page Application (SPA)**: All content on one page with smooth scrolling
- **Progressive Disclosure**: Menu sections are toggled (show/hide) based on user selection
- **Modal Pattern**: Reservation form appears as an overlay modal

---

## Key Features & Functionality

### 1. Navigation System
- **Fixed Navigation**: Nav bar becomes fixed on scroll (at 250px from top)
- **Smooth Scrolling**: Click navigation items to scroll to specific sections
- **Scroll Positions**:
  - Home: 1px
  - Menu: 740px
  - Gallery: 1500px
  - Location/Reservations: 2500px

### 2. Menu Display (js/main.js:2-23)
- **Three Categories**: Brunch, Dinner, Drinks
- **Toggle Behavior**: Clicking a category shows that section and hides others
- **Default State**: Both brunch and dinner sections are hidden on page load
- **CSS Grid Layout**: Each menu section uses CSS Grid for responsive layouts

### 3. Modal Reservation Form (js/main.js:72-79)
- **Trigger**: "Make Reservation" button in footer
- **Fields**: Full Name, Email, Time
- **Close Behavior**: Form submits and modal fades out
- **Styling**: Fixed position, semi-transparent backdrop

### 4. Scrolling Navigation Bar (js/main.js:55-70)
- **Threshold**: 250px scroll distance
- **Class Toggle**: Adds/removes `.scrolled` class to `nav`
- **Visual Effect**: Fixed positioning with background color change

### 5. Image Gallery
- **Current State**: Single static image display
- **Carousel Images Available**: 4 carousel images in `/images` directory
- **Potential Enhancement**: Gallery could be expanded to use carousel functionality

---

## CSS Architecture

### Layout Techniques
- **CSS Grid**: Primary layout method for menu sections
  - Brunch: 3-column grid
  - Dinner: 3-column grid
  - Drinks: 4-column grid with 2 image columns
  - Location: 2-column grid (1fr 2fr)

### Color Scheme
- **Primary Brand Color**: `#600710` (deep burgundy/wine red)
- **Hover State**: `#AF1D2C` (lighter red)
- **Background**: Black footer, white/transparent main sections
- **Text**: Black body text, white on dark backgrounds

### Typography
- **Font Family**: 'Open Sans', sans-serif
- **Heading Sizes**:
  - H1: 48px (sections), 90px (header title)
  - H2: 50px (sections), 26px (location subsections)
  - H3: 24px (general), 20px (menu items)
  - Body: 12px

### Responsive Design
- **Media Query**: `@media screen and (max-width: 600px)`
- **Mobile Adjustments**: Navigation link spacing reduced to 10px margin

---

## JavaScript Functionality

### jQuery Event Handlers

#### Menu Toggle System (js/main.js:2-23)
```javascript
$('#Brunch').on('click', ...) - Shows brunch, hides dinner & drinks
$('#Dinner').on('click', ...) - Shows dinner, hides brunch & drinks
$('#Drinks').on('click', ...) - Shows drinks, hides brunch & dinner
```

#### Scroll Navigation Functions (js/main.js:31-48)
```javascript
scrollWinH() - Home (1px)
scrollWin()  - Menu (740px)
scrollWinG() - Gallery (1500px)
scrollWinL() - Location (2500px)
scrollWinR() - Reservations (2500px)
```

#### Dynamic Nav Behavior (js/main.js:55-70)
- Monitors scroll position via `$(window).scrollTop()`
- Adds `.scrolled` class when scroll >= 250px
- Removes class when scroll < 250px

#### Modal Controls (js/main.js:72-79)
- Button click: `.fadeIn()` on modal and modal-box
- Form submit: `.fadeOut()` on both elements

---

## Development Workflows

### Git Branch Strategy
- **Feature Branches**: All development occurs on branches starting with `claude/`
- **Branch Naming**: `claude/<description>-<sessionId>`
- **Example**: `claude/add-claude-documentation-ygvCn`
- **Critical**: Never push to branches that don't follow this pattern (will result in 403 error)

### Git Operations Best Practices

#### Pushing Changes
```bash
# Always use -u flag for first push
git push -u origin claude/<branch-name>

# Retry logic for network failures: 4 attempts with exponential backoff (2s, 4s, 8s, 16s)
```

#### Fetching Updates
```bash
# Prefer specific branch fetches
git fetch origin <branch-name>

# For pulling changes
git pull origin <branch-name>
```

### Commit Guidelines
1. **Clear, descriptive messages**: Focus on "why" not just "what"
2. **Commit scope**: Align messages with changes (add, update, fix, refactor)
3. **No secrets**: Never commit `.env`, credentials, or sensitive files
4. **Sequential operations**: Use `&&` for dependent commands

---

## Code Conventions

### HTML Conventions
- **Indentation**: Use consistent indentation (Edit > Lines > Auto Indent in editor)
- **Comments**: Inline comments for organization and placeholders
- **Semantic Structure**: Proper use of `<header>`, `<nav>`, `<section>`, `<footer>`
- **Accessibility**: Include `aria-hidden` attributes on decorative icons

### CSS Conventions
- **Organization**: Comments mark major sections
- **Selectors**: Class-based for components, ID-based for unique elements
- **Box Model**: `box-sizing: border-box` globally applied
- **Units**: Mix of `px`, `fr` (grid), `vh` (viewport height)

### JavaScript Conventions
- **jQuery Style**: Use `$()` selectors and jQuery methods
- **Event Binding**: `.on('click', ...)` pattern for event handlers
- **Animation**: `.fadeIn()`, `.fadeOut()` for smooth transitions
- **Comments**: Inline explanations for complex logic

### Naming Conventions
- **CSS Classes**: Kebab-case (e.g., `.menu-header`, `.social-icons`)
- **IDs**: PascalCase for nav items (e.g., `#Brunch`, `#Dinner`, `#Home`)
- **Functions**: camelCase (e.g., `scrollWin()`, `scrollWinL()`)
- **Files**: Lowercase with hyphens for images (e.g., `home-header.jpg`)

---

## Common Development Tasks

### 1. Adding New Menu Items
**Files**: `index.html` (HTML structure), `css/style.css` (no changes usually needed)

1. Locate the appropriate section (`.brunch`, `.dinner`, `.drinks`)
2. Add a new `<div>` with `<h3>` (item name) and `<p>` (description)
3. CSS Grid will automatically handle layout

### 2. Updating Styles
**File**: `css/style.css`

- **Colors**: Search for `#600710` (primary) or `#AF1D2C` (hover) to maintain consistency
- **Typography**: Modify font-size in appropriate heading rules
- **Layout**: Adjust `grid-template-columns` for menu sections
- **Responsive**: Add rules within the `@media` query at line 319

### 3. Modifying JavaScript Behavior
**File**: `js/main.js`

- **Scroll Positions**: Update values in `scrollWin*()` functions if layout changes
- **Menu Toggle**: Add new category in pattern of existing handlers (lines 2-23)
- **Animations**: Adjust `.fadeIn()`/`.fadeOut()` or add jQuery animations

### 4. Image Management
**Directory**: `images/`

- **Optimization**: Images are high-resolution (up to 8MB); consider optimization for web
- **Naming**: Follow existing pattern (photographer-name-number.jpg)
- **References**: Update `src` attributes in HTML when changing images

### 5. Adding New Sections
1. Add HTML structure in `index.html`
2. Create corresponding CSS rules in `style.css`
3. Add navigation item in `<nav>` with `onclick="scrollWin*()"`
4. Create new scroll function in `main.js`
5. Update footer links if needed

---

## AI Assistant Guidelines

### When Working on This Codebase

#### DO:
- **Read Before Editing**: Always read files before making changes
- **Maintain Consistency**: Follow existing patterns for HTML structure, CSS naming, and JS event handling
- **Test Scroll Positions**: Verify scroll navigation targets if modifying layout
- **Check Dependencies**: Ensure jQuery and Font Awesome CDN links remain intact
- **Use Grid Layout**: Continue CSS Grid pattern for new menu sections
- **Preserve Brand Colors**: Use existing color scheme (`#600710`, `#AF1D2C`)
- **Comment Your Changes**: Add inline comments for non-obvious modifications

#### DON'T:
- **Don't Over-Engineer**: Keep solutions simple; this is a straightforward static site
- **Don't Break Single-File Pattern**: Maintain the single HTML/CSS/JS file structure
- **Don't Remove jQuery**: The entire interaction layer depends on jQuery
- **Don't Skip Testing**: Verify menu toggles, modal behavior, and scroll navigation
- **Don't Commit Large Images**: Be mindful of image file sizes (some are 3-8MB)
- **Don't Change Branch Patterns**: Always use `claude/*` branch naming

#### Common Pitfalls to Avoid:
1. **Scroll Position Hardcoding**: Values in `scrollWin*()` functions break if layout changes significantly
2. **Z-Index Conflicts**: Modal uses `z-index: 600-1000`; scrolled nav uses `z-index: 100`
3. **Grid Column Positioning**: Image divs use `grid-column` to position in specific columns
4. **Hidden Sections**: Brunch and dinner sections hidden by default (js/main.js:3-4)
5. **Fixed Modal Sizing**: Modal-box uses fixed width/height and margins (css/style.css:278-287)

### Context-Specific Guidance

#### For Bug Fixes:
- Check scroll positions if navigation isn't working
- Verify jQuery selectors match HTML IDs/classes
- Inspect CSS specificity if styles aren't applying
- Test modal backdrop click-through (currently not implemented)

#### For Feature Additions:
- **Gallery Carousel**: Use existing carousel images (carousel-1.jpg through carousel-4.jpg)
- **Form Validation**: Add validation before modal fadeOut in js/main.js:76-79
- **Mobile Menu**: Current responsive design is minimal; hamburger menu could improve UX
- **Smooth Scrolling**: Replace `window.scrollTo()` with jQuery `.animate()` for smoothness

#### For Refactoring:
- Consider extracting scroll positions to configuration object
- Modal could benefit from close button (currently only form submit closes it)
- Commented-out code (HTML lines 226-235, CSS lines 295-317) should be removed or restored
- DRY opportunity: Menu toggle handlers follow identical pattern

### Testing Checklist:
- [ ] Navigation bar becomes fixed at 250px scroll
- [ ] All nav items scroll to correct positions
- [ ] Menu categories toggle correctly (show/hide)
- [ ] Modal opens on button click
- [ ] Modal closes on form submit
- [ ] Social media icons display (Font Awesome)
- [ ] Images load correctly
- [ ] Responsive behavior at <600px width
- [ ] No console errors in browser developer tools

---

## Known Issues & Technical Debt

### Current Issues:
1. **Modal Accessibility**: No close button or ESC key handler
2. **Form Functionality**: Form has no backend; just closes on submit
3. **Gallery Feature**: Gallery shows single image; carousel not implemented
4. **Image Optimization**: Several images exceed 5MB
5. **Commented Code**: Unused HTML and CSS should be cleaned up (index.html:226-235, style.css:295-317)
6. **Typos in Content**: "ttomato", "tarugula", "corriander" (minor spelling errors)
7. **Hardcoded Scroll Values**: Brittle; breaks if layout significantly changes

### Enhancement Opportunities:
- Implement proper image carousel/slider for gallery
- Add form validation and backend integration
- Improve mobile responsiveness
- Add smooth scroll animations
- Implement modal backdrop click-to-close
- Add keyboard navigation support
- Optimize images for web (compression, responsive images)
- Consider using CSS custom properties for color scheme

---

## Quick Reference

### File Locations
- Main HTML: `/index.html`
- Styles: `/css/style.css`
- Scripts: `/js/main.js`
- Assets: `/images/`

### Key Code Locations
- Navigation: `index.html:22-31`
- Menu Sections: `index.html:45-147`
- Gallery: `index.html:150-153`
- Location: `index.html:156-179`
- Reservation Modal: `index.html:187-202`
- Footer: `index.html:186-214`
- Menu Toggle JS: `main.js:2-23`
- Scroll Functions: `main.js:31-48`
- Nav Scroll Behavior: `main.js:55-70`
- Modal Controls: `main.js:72-79`

### Important IDs & Classes
- **IDs**: `#Home`, `#Menu`, `#Location`, `#Reservations`, `#Gallery`, `#Brunch`, `#Dinner`, `#Drinks`
- **Classes**: `.brunch`, `.dinner`, `.drinks`, `.modal`, `.modal-box`, `.scrolled`, `.reservation-button`

### External Resources
- jQuery 3.2.1: https://code.jquery.com/jquery-3.2.1.min.js
- Font Awesome 4.7.0: https://maxcdn.bootstrapcdn.com/font-awesome/4.7.0/css/font-awesome.min.css

---

## Version History

- **Initial Commit** (6d4f504): Project foundation
- **Final Project** (87e4079): Current state with complete functionality
- **Current Branch**: `claude/add-claude-documentation-ygvCn` (documentation addition)

---

## Support & Resources

For questions about this codebase or to report issues:
- Check this CLAUDE.md file first
- Review git commit history for context on changes
- Test in browser developer tools for JavaScript debugging
- Use browser inspect element for CSS troubleshooting

**Last Updated**: 2026-01-21
**Document Version**: 1.0.0
