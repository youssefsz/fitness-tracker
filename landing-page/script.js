'use strict';

const root = document.documentElement;
const appearance = document.querySelector('#theme');
const systemTheme = window.matchMedia('(prefers-color-scheme: dark)');
const darkSources = document.querySelectorAll('source[data-dark]');
const themeIcons = { system: '#system-icon', light: '#sun-icon', dark: '#moon-icon' };

function updateAppearance(choice) {
  if (choice === 'system') {
    delete root.dataset.theme;
  } else {
    root.dataset.theme = choice;
  }

  for (const source of darkSources) {
    source.media = choice === 'system' ? systemTheme.media : choice === 'dark' ? 'all' : 'not all';
  }

  appearance.closest('label').querySelector('use').setAttribute('href', themeIcons[choice]);
  for (const meta of document.querySelectorAll('meta[name="theme-color"]')) {
    const systemQuery = meta.dataset.systemQuery || meta.media;
    meta.dataset.systemQuery = systemQuery;
    const matchesChoice = systemQuery.includes(choice);
    meta.media = choice === 'system' ? systemQuery : matchesChoice ? 'all' : 'not all';
  }
}

appearance.value = root.dataset.theme || 'system';
updateAppearance(appearance.value);
appearance.closest('label').hidden = false;
appearance.addEventListener('change', () => {
  updateAppearance(appearance.value);
  try {
    if (appearance.value === 'system') {
      localStorage.removeItem('fitness-tracker-theme');
    } else {
      localStorage.setItem('fitness-tracker-theme', appearance.value);
    }
  } catch {
    // The selection still applies to the current page.
  }
});
const tablist = document.querySelector('.feature-tabs');
const tabs = Array.from(tablist.querySelectorAll('button'));
const panels = tabs.map((tab) => document.getElementById(tab.getAttribute('aria-controls')));

function selectFeature(index, focus = false) {
  tabs.forEach((tab, position) => {
    const selected = position === index;
    tab.setAttribute('aria-selected', String(selected));
    tab.tabIndex = selected ? 0 : -1;
    panels[position].hidden = !selected;
  });

  if (focus) tabs[index].focus();
}

tablist.setAttribute('role', 'tablist');
tabs.forEach((tab, index) => {
  tab.setAttribute('role', 'tab');
  panels[index].setAttribute('role', 'tabpanel');
  panels[index].setAttribute('aria-labelledby', tab.id);
  panels[index].tabIndex = 0;
  tab.addEventListener('click', () => selectFeature(index));
});
tablist.addEventListener('keydown', (event) => {
  const current = tabs.indexOf(event.target);
  if (current === -1) return;

  const shortcuts = {
    ArrowRight: (current + 1) % tabs.length,
    ArrowLeft: (current - 1 + tabs.length) % tabs.length,
    Home: 0,
    End: tabs.length - 1,
  };
  if (!Object.hasOwn(shortcuts, event.key)) return;

  event.preventDefault();
  selectFeature(shortcuts[event.key], true);
});
selectFeature(tabs.findIndex((tab) => tab.hasAttribute('data-default')));
tablist.hidden = false;
