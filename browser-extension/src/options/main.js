import { getExtensionApi } from '../shared/browser-api.js';
import { bindOptions } from './options.js';

bindOptions(document, getExtensionApi());
