import { getExtensionApi } from '../shared/browser-api.js';
import { bindPopup } from './popup.js';

bindPopup(document, getExtensionApi());
