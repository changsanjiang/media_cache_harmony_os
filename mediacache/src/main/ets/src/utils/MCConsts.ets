namespace MCConsts {
  export const LOCALHOST = "127.0.0.1";
  export const ROUTE_PATH_PROXY_URL = "/mc_proxy"; // url(remote res)
  export const ROUTE_PATH_PROXY_DIR = "/mc_dir_proxy"; // dir(exported res)
  export const ROUTE_PATH_PROXY_BASED = "/mc_based_proxy"; // based url(dash res)
  // export const PATH_PIN = "/mc_pin"; // 貌似不需要pin;

  /** 允许的最大父路径层级数量（对应 ../ 的层数占位符） */
  export const DASH_PARENT_PATH_MAX_DEPTH = 8;

  /** 占位标记，用于代替 `../` 出现在路径中 */
  export const DASH_PARENT_PATH_PLACEHOLDER = "MC_DASH_BPP";
}

export default MCConsts;